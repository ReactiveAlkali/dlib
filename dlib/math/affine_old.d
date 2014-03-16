/*
Copyright (c) 2013 Timur Gafarov 

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

module dlib.math.affine;

import std.math;

import dlib.math.utils;
import dlib.math.vector;
import dlib.math.matrix;

/*
 * Affine transformations
 *
 * Affine transformation is a function between affine spaces
 * which preserves points, straight lines and planes.
 * Examples of affine transformations include translation, scaling, 
 * rotation, reflection, shear and compositions of them in any 
 * combination and sequence.
 *
 * dlib uses 4x4 matrices to represent affine transformations.
 */

/*
 * Setup a rotation matrix, given XYZ rotation angles
 */
Matrix!(T,4) fromEuler(T) (Vector!(T,3) v)
{
    auto res = Matrix!(T,4).identity;
    
    T cx = cos(v.x);
    T sx = sin(v.x);
    T cy = cos(v.y);
    T sy = sin(v.y);
    T cz = cos(v.z);
    T sz = sin(v.z);

    T sxsy = sx * sy;
    T cxsy = cx * sy;

    res.a11 =  (cy * cz);
    res.a12 =  (sxsy * cz) + (cx * sz);
    res.a13 = -(cxsy * cz) + (sx * sz);

    res.a21 = -(cy * sz);
    res.a22 = -(sxsy * sz) + (cx * cz);
    res.a23 =  (cxsy * sz) + (sx * cz);

    res.a31 =  (sy);
    res.a32 = -(sx * cy);
    res.a33 =  (cx * cy);

    return res;
}

/*
 * Setup the euler angles in radians, given a rotation matrix
 */
Vector!(T,3) toEuler(T) (Matrix!(T,4) m)
body
{
    Vector!(T,3) v;

    v.y = asin(m.a31);

    T cy = cos(v.y);
    T oneOverCosY = 1.0 / cy;

    if (fabs(cy) > 0.001)
    {
        v.x = atan2(-m.a32 * oneOverCosY, m.a33 * oneOverCosY);
        v.z = atan2(-m.a21 * oneOverCosY, m.a11 * oneOverCosY);
    }
    else
    {
        v.x = 0.0;
        v.z = atan2(m.a12, m.a22);
    }

    return v;
}

/*
 * Right vector of the matrix
 */
Vector!(T,3) right(T) (Matrix!(T,4) m)
body
{
    return Vector!(T,3)(m.a11, m.a12, m.a13);
}

/*
 * Up vector of the matrix
 */
Vector!(T,3) up(T) (Matrix!(T,4) m)
body
{
    return Vector!(T,3)(m.a21, m.a22, m.a23);
}

/*
 * Forward vector of the matrix
 */
Vector!(T,3) forward(T) (Matrix!(T,4) m)
body
{
    return Vector!(T,3)(m.a31, m.a32, m.a33);
}

/*
 * Translation vector of the matrix
 */
Vector!(T,3) translation(T) (Matrix!(T,4) m)
body
{
    return Vector!(T,3)(m.a41, m.a42, m.a43);
}

/*
 * Scaling vector of the matrix
 */
Vector!(T,3) scaling(T) (Matrix!(T,4) m)
body
{
    return Vector!(T,3)(m.a11, m.a22, m.a33);
}

/* 
 * Create a matrix to perform a rotation about an arbitrary axis
 * (theta in radians)
 */
Matrix!(T,4) rotationMatrix(T) (int rotaxis, T theta)
body
{
    auto res = Matrix!(T,4).identity;

    T s = sin(theta);
    T c = cos(theta);

    switch (rotaxis)
    {
        case Axis.x:
            res.a11 = 1.0; res.a21 = 0.0; res.a31 = 0.0;
            res.a12 = 0.0; res.a22 = c;   res.a32 = -s;
            res.a13 = 0.0; res.a23 = s;   res.a33 =  c;
            break;

        case Axis.y:
            res.a11 = c;   res.a21 = 0.0; res.a31 = s;
            res.a12 = 0.0; res.a22 = 1.0; res.a32 = 0.0;
            res.a13 = -s;  res.a23 = 0.0; res.a33 = c;
            break;

        case Axis.z:
            res.a11 = c;   res.a21 = -s;  res.a31 = 0.0;
            res.a12 = s;   res.a22 =  c;  res.a32 = 0.0;
            res.a13 = 0.0; res.a23 = 0.0; res.a33 = 1.0;
            break;

        default:
            assert(0);
    }

    return res;
}

/* 
 * Create a translation matrix given a translation vector
 */
Matrix!(T,4) translationMatrix(T) (Vector!(T,3) v)
body
{
    auto res = Matrix!(T,4).identity;
    res.a41 = v.x;
    res.a42 = v.y;
    res.a43 = v.z;
    return res;
}

/*
 * Create a matrix to perform scale on each axis
 */
Matrix!(T,4) scaleMatrix(T) (Vector!(T,3) v)
body
{
    auto res = Matrix!(T,4).identity;
    res.a11 = v.x;  
    res.a22 = v.y;
    res.a33 = v.z;
    return res;
}

/*
 * Setup the matrix to perform scale along an arbitrary axis
 */
Matrix!(T,4) scaleAlongAxisMatrix(T) (Vector!(T,3) scaleAxis, T k)
in
{
    assert (fabs (dot(scaleAxis, scaleAxis) - 1.0) < 0.001);
}
body
{
    auto res = Matrix!(T,4).identity;

    T a = k - 1.0;
    T ax = a * scaleAxis.x;
    T ay = a * scaleAxis.y;
    T az = a * scaleAxis.z;

    res.a11 = (ax * scaleAxis.x) + 1.0;
    res.a22 = (ay * scaleAxis.y) + 1.0;
    res.a32 = (az * scaleAxis.z) + 1.0;

    res.a12 = res.a21 = (ax * scaleAxis.y);
    res.a13 = res.a31 = (ax * scaleAxis.z);
    res.a23 = res.a32 = (ay * scaleAxis.z);

    return res;
}

/*
 * Setup the matrix to perform a shear
 */
Matrix!(T,4) shearMatrix(T) (int shearAxis, T s, T t)
body
{
    auto res = Matrix!(T,4).identity;

    switch (shearAxis)
    {
        case Axis.x:
            res.a11 = 1.0; res.a21 = 0.0; res.a31 = 0.0;
            res.a12 = s;   res.a22 = 1.0; res.a32 = 0.0;
            res.a13 = t;   res.a23 = 0.0; res.a33 = 1.0;
            break;

        case Axis.y:
            res.a11 = 1.0; res.a21 = s;   res.a31 = 0.0;
            res.a12 = 0.0; res.a22 = 1.0; res.a32 = 0.0;
            res.a13 = 0.0; res.a23 = t;   res.a33 = 1.0;
            break;

        case Axis.z:
            res.a11 = 1.0; res.a21 = 0.0; res.a31 = s;
            res.a12 = 0.0; res.a22 = 1.0; res.a32 = t;
            res.a13 = 0.0; res.a23 = 0.0; res.a33 = 1.0;
            break;

        default:
            assert(0);
    }

    return res;
}

/* 
 * Setup the matrix to perform a projection onto a plane passing
 * through the origin. The plane is perpendicular to the
 * unit vector n.
 */
Matrix!(T,4) projectionMatrix(T) (Vector!(T,3) n)
in
{
    assert (fabs(dot(n, n) - 1.0) < 0.001);
}
body
{
    auto res = Matrix!(T,4).identity;

    res.a11 = 1.0 - (n.x * n.x);
    res.a22 = 1.0 - (n.y * n.y);
    res.a33 = 1.0 - (n.z * n.z);

    res.a12 = res.a21 = -(n.x * n.y);
    res.a13 = res.a31 = -(n.x * n.z);
    res.a23 = res.a32 = -(n.y * n.z);

    return res;
}

/*
 * Setup the matrix to perform a reflection about a plane parallel
 * to a cardinal plane.
 */
Matrix!(T,4) reflectionMatrix(T) (Axis reflectionAxis, T k)
body
{
    auto res = Matrix!(T,4).identity;

    switch (reflectionAxis)
    {
        case Axis.x:
            res.a11 = -1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 2.0 * k;
            res.a12 =  0.0; res.a22 =  1.0; res.a32 =  0.0; res.a42 = 0.0;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 =  1.0; res.a43 = 0.0;
            break;

        case Axis.y:
            res.a11 =  1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 0.0;
            res.a12 =  0.0; res.a22 = -1.0; res.a32 =  0.0; res.a42 = 2.0 * k;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 =  1.0; res.a43 = 0.0;
            break;

        case Axis.z:
            res.a11 =  1.0; res.a21 =  0.0; res.a31 =  0.0; res.a41 = 0.0;
            res.a12 =  0.0; res.a22 =  1.0; res.a32 =  0.0; res.a42 = 0.0;
            res.a13 =  0.0; res.a23 =  0.0; res.a33 = -1.0; res.a43 = 2.0 * k;
            break;

        default:
            assert(0);
    }

    return res;
}

/*
 * Setup the matrix to perform a reflection about an arbitrary plane
 * through the origin.  The unit vector n is perpendicular to the plane.
 */
Matrix!(T,4) axisReflectionMatrix(T) (Vector!(T,3) n)
in
{
    assert (fabs(dot(n, n) - 1.0) < 0.001);
}
body
{
    auto res = Matrix!(T,4).identity;

    T ax = -2.0 * n.x;
    T ay = -2.0 * n.y;
    T az = -2.0 * n.z;

    res.a11 = 1.0 + (ax * n.x);
    res.a22 = 1.0 + (ay * n.y);
    res.a32 = 1.0 + (az * n.z);

    res.a12 = res.a21 = (ax * n.y);
    res.a13 = res.a31 = (ax * n.z);
    res.a23 = res.a32 = (ay * n.z);

    return res;
}

/*
 * Setup the matrix to perform a "Look At" transformation 
 * like a first person camera
 */
Matrix!(T,4) lookAtMatrix(T) (Vector!(T,3) camPos, Vector!(T,3) target, Vector!(T,3) camUp)
body
{
    auto rot = Matrix!(T,4).identity;

    Vector!(T,3) forward = (camPos - target).normalized;
    Vector!(T,3) right = cross(camUp, forward).normalized;
    Vector!(T,3) up = cross(forward, right).normalized;

    rot.a11 = right.x;
    rot.a21 = right.y;
    rot.a31 = right.z;

    rot.a12 = up.x;
    rot.a22 = up.y;
    rot.a32 = up.z;

    rot.a13 = forward.x;
    rot.a23 = forward.y;
    rot.a33 = forward.z;

    auto trans = translationMatrix(-camPos);
    return (rot * trans);
}

/*
 * Setup a frustum matrix given the left, right, bottom, top, near, and far
 * values for the frustum boundaries.
 */
Matrix!(T,4) frustumMatrix(T) (T l, T r, T b, T t, T n, T f)
in
{
    assert (n >= 0.0);
    assert (f >= 0.0);
}
body
{
    auto res = Matrix!(T,4).identity;

    T width  = r - l;
    T height = t - b;
    T depth  = f - n;

    res.arrayof[0] = (2 * n) / width;
    res.arrayof[1] = 0.0;
    res.arrayof[2] = 0.0;
    res.arrayof[3] = 0.0;

    res.arrayof[4] = 0.0;
    res.arrayof[5] = (2 * n) / height;
    res.arrayof[6] = 0.0;
    res.arrayof[7] = 0.0;

    res.arrayof[8] = (r + l) / width;
    res.arrayof[9] = (t + b) / height;
    res.arrayof[10]= -(f + n) / depth;
    res.arrayof[11]= -1.0;

    res.arrayof[12]= 0.0;
    res.arrayof[13]= 0.0;
    res.arrayof[14]= -(2 * f * n) / depth;
    res.arrayof[15]= 0.0;

    return res;
}

/*
 * Setup a perspective matrix given the field-of-view in the Y direction
 * in degrees, the aspect ratio of Y/X, and near and far plane distances
 */
Matrix!(T,4) perspectiveMatrix(T) (T fovY, T aspect, T n, T f)
body
{
    auto res = Matrix!(T,4).identity;

    T angle;
    T cot;

    angle = fovY / 2.0;
    angle = degtorad(angle);

    cot = cos(angle) / sin(angle);

    res.arrayof[0] = cot / aspect;
    res.arrayof[1] = 0.0;
    res.arrayof[2] = 0.0;
    res.arrayof[3] = 0.0;

    res.arrayof[4] = 0.0;
    res.arrayof[5] = cot;
    res.arrayof[6] = 0.0;
    res.arrayof[7] = 0.0;

    res.arrayof[8] = 0.0;
    res.arrayof[9] = 0.0;
    res.arrayof[10]= -(f + n) / (f - n);
    res.arrayof[11]= -1.0;

    res.arrayof[12]= 0.0;
    res.arrayof[13]= 0.0;
    res.arrayof[14]= -(2 * f * n) / (f - n);
    res.arrayof[15]= 0.0;

    return res;
}

/*
 * Setup an orthographic Matrix4x4 given the left, right, bottom, top, near,
 * and far values for the frustum boundaries.
 */
Matrix!(T,4) orthoMatrix(T) (T l, T r, T b, T t, T n, T f)
body
{
    auto res = Matrix!(T,4).identity;

    T width  = r - l;
    T height = t - b;
    T depth  = f - n;

    res.arrayof[0] =  2.0 / width;
    res.arrayof[1] =  0.0;
    res.arrayof[2] =  0.0;
    res.arrayof[3] =  0.0;

    res.arrayof[4] =  0.0;
    res.arrayof[5] =  2.0 / height;
    res.arrayof[6] =  0.0;
    res.arrayof[7] =  0.0;

    res.arrayof[8] =  0.0;
    res.arrayof[9] =  0.0;
    res.arrayof[10]= -2.0 / depth;
    res.arrayof[11]=  0.0;

    res.arrayof[12]= -(r + l) / width;
    res.arrayof[13]= -(t + b) / height;
    res.arrayof[14]= -(f + n) / depth;
    res.arrayof[15]=  1.0;

    return res;
}

/*
 * Setup an orientation matrix using 3 basis normalized vectors
 */
Matrix!(T,4) orthoNormalMatrix(T) (Vector!(T,3) xdir, Vector!(T,3) ydir, Vector!(T,3) zdir)
body
{
    auto res = Matrix!(T,4).identity;

    res.arrayof[0] = xdir.x; res.arrayof[4] = ydir.x; res.arrayof[8] = zdir.x; res.arrayof[12] = 0.0;
    res.arrayof[1] = xdir.y; res.arrayof[5] = ydir.y; res.arrayof[9] = zdir.y; res.arrayof[13] = 0.0;
    res.arrayof[2] = xdir.z; res.arrayof[6] = ydir.z; res.arrayof[10]= zdir.z; res.arrayof[14] = 0.0;
    res.arrayof[3] = 0.0;    res.arrayof[7] = 0.0;    res.arrayof[11]= 0.0;    res.arrayof[15] = 1.0;

    return res;
}

/*
 * Setup a matrix that flattens geometry into a plane, 
 * as if it were casting a shadow from a light
 */
Matrix!(T,4) shadowMatrix(T) (Vector!(T,4) groundplane, Vector!(T,4) lightpos)
{
    T d = dot(groundplane, lightpos);

    auto res = Matrix!(T,4).identity;

    res.a11 = d-lightpos.x * groundplane.x;
    res.a21 =  -lightpos.x * groundplane.y;
    res.a31 =  -lightpos.x * groundplane.z;
    res.a41 =  -lightpos.x * groundplane.w;

    res.a12 =  -lightpos.y * groundplane.x;
    res.a22 = d-lightpos.y * groundplane.y;
    res.a32 =  -lightpos.y * groundplane.z;
    res.a42 =  -lightpos.y * groundplane.w;

    res.a13 =  -lightpos.z * groundplane.x;
    res.a23 =  -lightpos.z * groundplane.y;
    res.a33 = d-lightpos.z * groundplane.z;
    res.a43 =  -lightpos.z * groundplane.w;

    res.a14 =  -lightpos.w * groundplane.x;
    res.a24 =  -lightpos.w * groundplane.y;
    res.a34 =  -lightpos.w * groundplane.z;
    res.a44 = d-lightpos.w * groundplane.w;
    
    return res;
}

/*
 * Setup an orientation matrix using forward direction vector
 */
Matrix!(T,4) directionToMatrix(T) (Vector!(T,3) zdir)
{
    Vector!(T,3) xdir = Vector!(T,3)(0.0, 0.0, 1.0);
    Vector!(T,3) ydir;
    float d = zdir.z;

    if (d > -0.999999999 && d < 0.999999999)
    {
        xdir = xdir - zdir * d;
        xdir.normalize();
        ydir = cross(zdir, xdir);
    }
    else
    {
        xdir = Vector!(T,3)(zdir.z, 0.0, -zdir.x);
        ydir = Vector!(T,3)(0.0, 1.0, 0.0);
    }

    Matrix4x4!(T) m = identityMatrix4x4!T();
    m.forward = zdir;
    m.right = xdir;
    m.up = ydir;

    return m;
}

/*
 * Setup an orientation matrix that performs rotation
 * between two vectors 
 */
Matrix!(T,4) rotationBetweenVectors(T) (Vector!(T,3) source, Vector!(T,3) target)
{
    T d = dot(source, target);
    Vector!(T,3) c = cross(source, target);
    c.normalize();
    return matrixFromAxisAngle(c, acos(d));
}

/*
 * Transformations in 2D space
 */
Matrix!(T,2) rotation(T) (T theta)
body
{
    Matrix!(T,2) res;
    T s = sin(theta);
    T c = cos(theta);
    res.a11 = c; res.a21 = -s;
    res.a12 = s; res.a22 = c;
    return res;
}

Matrix!(T,2) tensorProduct(T) (Vector!(T,2) u, Vector!(T,2) v)
body
{
    Matrix!(T,2) res;
    res[0] = u[0] * v[0];
    res[1] = u[0] * v[1];
    res[2] = u[1] * v[0];
    res[3] = u[1] * v[1];
    return res;
}
