/*
Copyright (c) 2016 Timur Gafarov 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * Copyright: Eugene Wissner 2016-.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Eugene Wissner
 *
 * If you changed the the default allocator please use $(D_PSYMBOL MmapPool)
 * to allocate watchers.
 *
 * ---
 * import dlib.memory;
 * import dlib.memory.mmappool;
 * import dlib.async;
 * import std.exception;
 * import core.sys.posix.netinet.in_;
 * import core.sys.posix.fcntl;
 * import core.sys.posix.unistd;
 *
 * class EchoProtocol : TransmissionControlProtocol
 * {
 *     private DuplexTransport transport;
 *
 *     void received(ubyte[] data)
 *     {
 *         transport.write(data);
 *     }
 *
 *     void connected(DuplexTransport transport)
 *     {
 *         this.transport = transport;
 *     }
 *
 *     void disconnected()
 *     {
 *     }
 * }
 *
 * void main()
 * {
 *     sockaddr_in addr;
 *     int s = socket(AF_INET, SOCK_STREAM, 0);
 *
 *     addr.sin_family = AF_INET;
 *     addr.sin_port = htons(cast(ushort)8192);
 *     addr.sin_addr.s_addr = INADDR_ANY;
 *
 *     if (bind(s, cast(sockaddr *)&addr, addr.sizeof) != 0)
 *     {
 *         throw MmapPool.instance.make!Exception("bind");
 *     }
 *
 *     fcntl(s, F_SETFL, fcntl(s, F_GETFL, 0) | O_NONBLOCK); 
 *     listen(s, 5);
 *
 *     auto io = MmapPool.instance.make!ConnectionWatcher(s);
 *     io.setProtocol!EchoProtocol;
 *
 *     defaultLoop.start(io);
 *
 *     defaultLoop.run();
 *
 *     shutdown(s, SHUT_RDWR);
 *     close(s);
 * }
 * ---
 */
module dlib.async.loop;

import dlib.async.protocol;
import dlib.async.transport;
import dlib.async.watcher;
import dlib.container.buffer;
import dlib.memory;
import dlib.memory.mmappool;
import dlib.network.socket;
import core.time;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.typecons;

version (DisableBackends)
{
}
else version (linux)
{
	import dlib.async.epoll;
	version = Epoll;
}

shared static this()
{
    if (allocator is null)
    {
        allocator = MmapPool.instance;
    }
}

/**
 * Events.
 */
enum Event : uint
{
    none   = 0x00, /// No events.
    read   = 0x01, /// Non-blocking read call.
    write  = 0x02, /// Non-blocking write call.
    accept = 0x04, /// Connection made.
}

alias EventMask = BitFlags!Event;

/**
 * Event loop.
 */
abstract class Loop
{
    /// Pending watchers.
    protected PendingQueue pendings;

    protected PendingQueue swapPendings;

	/// Max events can be got at a time (should be supported by the backend).
	protected enum maxEvents = 128;

    /// Pending connections.
    protected ConnectionWatcher[] connections;

    /**
     * Initializes the loop.
     */
    this()
    {
        connections = MmapPool.instance.makeArray!ConnectionWatcher(maxEvents);
        pendings = MmapPool.instance.make!(PendingQueue);
        swapPendings = MmapPool.instance.make!(PendingQueue);
    }

    /**
     * Frees loop internals.
     */
    ~this()
    {
		foreach (ref connection; connections)
		{
			// We want to free only IOWatchers. ConnectionWatcher are created by the
			// user and should be freed by himself.
			auto io = cast(IOWatcher) connection;
			if (io !is null)
			{
				MmapPool.instance.dispose(io);
				connection = null;
			}
		}
        MmapPool.instance.dispose(connections);
        MmapPool.instance.dispose(pendings);
        MmapPool.instance.dispose(swapPendings);
    }

    /**
     * Starts the loop.
     */
    void run()
    {
        done_ = false;
        do
        {
            poll();

            // Invoke pendings
            swapPendings.each!((ref p) => p.invoke());

            swap(pendings, swapPendings);
        }
        while (!done_);
    }

    /**
     * Break out of the loop.
     */
    void unloop() @safe pure nothrow
    {
        done_ = true;
    }

    /**
     * Start watching.
     *
     * Params:
     *     watcher = Watcher.
     */
    void start(ConnectionWatcher watcher)
    {
        if (watcher.active)
        {
            return;
        }
        watcher.active = true;
        watcher.accept = &acceptConnection;
        if (connections.length <= watcher.socket)
        {
            MmapPool.instance.expandArray(connections, maxEvents / 2);
        }
        connections[cast(int) watcher.socket] = watcher;

        modify(watcher.socket, EventMask(Event.none), EventMask(Event.accept));
    }

    /**
     * Stop watching.
     *
     * Params:
     *     watcher = Watcher.
     */
    void stop(ConnectionWatcher watcher)
    {
        if (!watcher.active)
        {
            return;
        }
        watcher.active = false;

        modify(watcher.socket, EventMask(Event.accept), EventMask(Event.none));
    }

    /**
     * Feeds the given event set into the event loop, as if the specified event
     * had happened for the specified watcher.
     *
     * Params:
     *     transport = Affected transport.
     */
    void feed(DuplexTransport transport)
    {
        pendings.insertBack(connections[cast(int) transport.socket]);
    }

    /**
     * Should be called if the backend configuration changes.
     *
     * Params:
     *     socket    = Socket.
     *     oldEvents = The events were already set.
     *     events    = The events should be set.
     *
     * Returns: $(D_KEYWORD true) if the operation was successful.
     */
    abstract protected bool modify(Socket socket,
	                               EventMask oldEvents,
	                               EventMask events);

    /**
     * Returns: The blocking time.
     */
    protected @property inout(Duration) blockTime()
    inout @safe pure nothrow
    {
        // Don't block if we have to do.
        return swapPendings.empty ? blockTime_ : Duration.zero;
    }

    /**
     * Sets the blocking time for IO watchers.
     *
     * Params:
     *     blockTime = The blocking time. Cannot be larger than
     *                 $(D_PSYMBOL maxBlockTime).
     */
    protected @property void blockTime(in Duration blockTime) @safe pure nothrow
    in
    {
        assert(blockTime <= 1.dur!"hours", "Too long to wait.");
        assert(!blockTime.isNegative);
    }
    body
    {
        blockTime_ = blockTime;
    }

    /**
     * Does the actual polling.
     */
    abstract protected void poll();

    /**
     * Accept incoming connections.
     *
     * Params:
     *     protocolFactory = Protocol factory.
     *     socket          = Socket.
     */
    protected void acceptConnection(Protocol delegate() protocolFactory,
                                    Socket socket);

    /// Whether the event loop should be stopped.
    private bool done_;

    /// Maximal block time.
    protected Duration blockTime_ = 1.dur!"minutes";
}

/**
 * Exception thrown on errors in the event loop.
 */
class BadLoopException : Exception
{
@nogc:
    /**
     * Params:
     *     file = The file where the exception occurred.
     *     line = The line number where the exception occurred.
     *     next = The previous exception in the chain of exceptions, if any.
     */
    this(string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    pure @safe nothrow const
    {
        super("Event loop cannot be initialized.", file, line, next);
    }
}

/**
 * Returns the event loop used by default. If an event loop wasn't set with
 * $(D_PSYMBOL defaultLoop) before, $(D_PSYMBOL defaultLoop) will try to
 * choose an event loop supported on the system.
 *
 * Returns: The default event loop.
 */
@property Loop defaultLoop()
{
    if (defaultLoop_ !is null)
    {
        return defaultLoop_;
    }
    version (Epoll)
    {
        defaultLoop_ = MmapPool.instance.make!EpollLoop;
    }
    return defaultLoop_;
}

/**
 * Sets the default event loop.
 *
 * This property makes it possible to implement your own backends or event
 * loops, for example, if the system is not supported or if you want to
 * extend the supported implementation. Just extend $(D_PSYMBOL Loop) and pass
 * your implementation to this property.
 *
 * Params:
 *     loop = The event loop.
 */
@property void defaultLoop(Loop loop)
in
{
    assert(loop !is null);
}
body
{
    defaultLoop_ = loop;
}

private Loop defaultLoop_;

/**
 * Queue.
 *
 * Params:
 *     T = Content type.
 */
class PendingQueue
{
    /**
     * Creates a new $(D_PSYMBOL Queue).
     */
    this()
    {
    }

    /**
     * Removes all elements from the queue.
     */
    ~this()
    {
        foreach (e; this)
        {
            MmapPool.instance.dispose(e);
        }
    }

    /**
     * Returns: First element.
     */
    @property ref Watcher front()
    in
    {
        assert(!empty);
    }
    body
    {
        return first.next.content;
    }

    /**
     * Inserts a new element.
     *
     * Params:
     *     x = New element.
     *
     * Returns: $(D_KEYWORD this).
     */
    typeof(this) insertBack(Watcher x)
    {
        Entry* temp = MmapPool.instance.make!Entry;
        
        temp.content = x;

        if (empty)
        {
            first.next = rear = temp;
        }
        else
        {
            rear.next = temp;
            rear = rear.next;
        }

        return this;
    }

    alias insert = insertBack;

    /**
     * Inserts a new element.
     *
     * Params:
     *     x = New element.
     *
     * Returns: $(D_KEYWORD this).
     */
    typeof(this) opOpAssign(string Op)(ref T x)
        if (Op == "~")
    {
        return insertBack(x);
    }

    /**
     * Returns: $(D_KEYWORD true) if the queue is empty.
     */
    @property bool empty() const @safe pure nothrow
    {
        return first.next is null;
    }

    /**
     * Move position to the next element.
     *
     * Returns: $(D_KEYWORD this).
     */
    typeof(this) popFront()
    in
    {
        assert(!empty);
    }
    body
    {
        auto n = first.next.next;

        MmapPool.instance.dispose(first.next);
        first.next = n;

        return this;
    }

    /**
     * Queue entry.
     */
    protected struct Entry
    {
        /// Queue item content.
        Watcher content;

        /// Next list item.
        Entry* next;
    }

    /// The first element of the list.
    protected Entry first;

    /// The last element of the list.
    protected Entry* rear;
}
