/*
Copyright (c) 2015-2021 Timur Gafarov

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
 * Dual quaternions
 *
 * Copyright: Timur Gafarov 2015-2021.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.math.dualquaternion;

import std.math;
import std.range;
import std.format;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import dlib.math.dual;

/**
 * Dual quaternion representation.
 * Dual quaternion is a generalization of quaternion to dual numbers field.
 * Similar to the way that simple quaternion represents rotation in 3D space,
 * dual quaternion represents rigid 3D transformation (translation + rotation),
 * so it can be used in kinematics.
 */
struct DualQuaternion(T)
{
    this(Quaternion!(T) q1, Quaternion!(T) q2)
    {
        this.q1 = q1;
        this.q2 = q2;
    }

    this(Quaternion!(T) r, Vector!(T,3) t)
    {
        this.q1 = r;
        this.q2 = Quaternion!(T)(t * 0.5, 0.0) * r;
    }

    this(Quaternion!(T) r)
    {
        this.q1 = r;
        this.q2 = Quaternion!(T).identity * r;
    }

    this(Vector!(T,3) t)
    {
        this.q1 = Quaternion!(T).identity;
        this.q2 = Quaternion!(T)(t * 0.5, 0.0);
    }

    Vector!(T,3) transform(Vector!(T,3) v)
    {
        auto vq = DualQuaternion!(T)(
            Quaternion!(T).identity,
            Quaternion!(T)(v.x, v.y, v.z, 0.0));
        auto q = this * vq * this.fullConjugate;
        return q.q2.xyz;
    }

    Vector!(T,3) rotate(Vector!(T,3) v)
    {
        return q1.rotate(v);
    }

    DualQuaternion!(T) conjugate()
    {
        return DualQuaternion!(T)(q1.conj, q2.conj);
    }

    DualQuaternion!(T) dualConjugate()
    {
        return DualQuaternion!(T)(q1, q2 * -1.0);
    }

    DualQuaternion!(T) fullConjugate()
    {
        return DualQuaternion!(T)(q1.conj, q2.conj * -1.0);
    }

    DualQuaternion!(T) opBinary(string op)(DualQuaternion!(T) d) if (op == "*")
    {
        return DualQuaternion!(T)(q1 * d.q1, q1 * d.q2 + q2 * d.q1);
    }

    DualQuaternion!(T) opBinary(string op)(DualQuaternion!(T) d) if (op == "+")
    {
        return DualQuaternion!(T)(q1 + d.q1, q2 + d.q2);
    }

    DualQuaternion!(T) opBinary(string op)(DualQuaternion!(T) d) if (op == "-")
    {
        return DualQuaternion!(T)(q1 - d.q1, q2 - d.q2);
    }

   /**
    * Rotation part
    */
    Quaternion!(T) rotation()
    {
        return q1;
    }

   /**
    * Translation part
    */
    Vector!(T,3) translation()
    {
        return (2.0 * q2 * q1.conj).xyz;
    }

   /**
    * Convert to 4x4 matrix
    */
    Matrix!(T,4) toMatrix4x4()
    {
        // TODO: Can this be done without matrix multiplication?
        return translationMatrix(translation) * rotation.toMatrix4x4;
    }

   /**
    * Dual quaternion norm
    */
    Dual!(T) norm()
    {
        auto qq = this * this.conjugate;
        return Dual!(T)(qq.q1.lengthsqr, qq.q2.lengthsqr).sqrt;
    }

   /**
    * Set norm to 1
    */
    DualQuaternion!(T) normalized()
    {
        Dual!(T) n = norm;
        return DualQuaternion!(T)(q1 / n.re, q2 / n.re);
    }

   /**
    * Convert to string
    */
    string toString()
    {
        auto writer = appender!string();
        formattedWrite(writer, "[%s, %s]", q1.arrayof, q2.arrayof);
        return writer.data;
    }

   /**
    * Elements union
    */
    union
    {
        struct
        {
            /// Rotation part
            Quaternion!(T) q1;
            
            /// Translation part
            Quaternion!(T) q2;
        }

        /// Elements as static array
        T[8] arrayof;
    }
}

/// Alias for single precision DualQuaternion specialization
alias DualQuaternionf = DualQuaternion!(float);

/// Alias for double precision DualQuaternion specialization
alias DualQuaterniond = DualQuaternion!(double);

///
unittest
{
    Quaternionf r1 = rotationQuaternion!float(0, PI * 0.5f);
    Vector3f t1 = Vector3f(1.0f, 0.0f, 0.0f);
    DualQuaternionf dq1 = DualQuaternionf(r1, t1);
    assert(dq1.rotation == r1);
    assert(isAlmostZero(dq1.translation - t1));
    
    Vector3f v = dq1.rotate(Vector3f(0.0f, 1.0f, 0.0f));
    assert(isAlmostZero(v - Vector3f(0.0f, 0.0f, 1.0f)));
}
