/*
 *  FFGLPool.c
 *  VVFFGL
 *
 *  Created by Tom on 04/11/2009.
 *  Copyright 2009 Tom Butterworth. All rights reserved.
 *
 */

#include "FFGLPool.h"
#import <stdlib.h>
#import <libkern/OSAtomic.h>

static void _FFGLPoolObjectDispose(FFGLPoolObjectRef object);

/*
 Note on locking.
 Retain/release is done using OSAtomic operations, easy.
 Pool mutation uses OSSpinLocks, which are suited to low-contention locking
 (and in such situations are very fast to acquire).
 It is important that no calls are made to user create/destroy callbacks from
 within a lock. Pool mutation is very fast and so contention is unlikely in locking.
 User object creation/destruction is likely to be slow, so contention becomes likely.
 
 For this reason, user callbacks must themselves be thread-safe, or pools be used in
 a thread-safe manner.
 
 Current implementation observes this.
 */

typedef struct FFGLPool
{
    int32_t retainc;
    OSSpinLock lock;
    FFGLPoolCallBacks callbacks;
    const void *useri;
    unsigned int size;
    unsigned int level;
    FFGLPoolObjectRef *members;
} FFGLPool;

typedef struct FFGLPoolObject
{
	int32_t retainc;
	FFGLPoolRef pool;
	const void *object;
} FFGLPoolObject;

FFGLPoolRef FFGLPoolCreate(FFGLPoolCallBacks *callbacks, unsigned int sizeMax, const void *userInfo)
{
    if (callbacks == NULL || sizeMax == 0)
        return NULL;
    FFGLPoolRef new = malloc(sizeof(FFGLPool));
    if (new)
    {
        new->members = malloc(sizeof(FFGLPoolObjectRef) * sizeMax);
        if (new->members == NULL)
        {
            free(new);
            return NULL;
        }
        new->callbacks.create = callbacks->create;
        new->callbacks.destroy = callbacks->destroy;
        new->useri = userInfo;
        new->size = sizeMax;
        new->level = 0;
        new->lock = OS_SPINLOCK_INIT;
        new->retainc = 1;
    }
    return new;
}

FFGLPoolRef FFGLPoolRetain(FFGLPoolRef pool)
{
    if (pool)
        OSAtomicIncrement32Barrier(&pool->retainc);
    return pool;
}

void FFGLPoolRelease(FFGLPoolRef pool)
{
    if (pool)
    {
        if (OSAtomicDecrement32Barrier(&pool->retainc) == 0) {
            for (unsigned int i = 0; i < pool->level; i++)
            {
                _FFGLPoolObjectDispose(pool->members[i]);
            }
            free(pool->members);
            free(pool);
        }
    }
}

FFGLPoolObjectRef FFGLPoolObjectCreate(FFGLPoolRef pool)
{
    if (pool == NULL)
        return NULL;
    FFGLPoolObjectRef new = NULL;
    // lock pool for mutation
    OSSpinLockLock(&pool->lock);
    // check pool for available object
    if (pool->level > 0)
    {
        // the pool has objects, so decrement the level counter
        // and get the top-most one
        new = pool->members[--pool->level];
    }
    // unlock, mutation over
    OSSpinLockUnlock(&pool->lock);
    if (new == NULL)
    {
        // no object was available
        // create a new object
        new = malloc(sizeof(FFGLPoolObject));
        if (new)
        {
            new->object = pool->callbacks.create(pool->useri);
            new->pool = pool;
            if (new->object == NULL)
            {
                // empty objects are no use to man nor beast
                // consider this failure
                free(new);
                new = NULL;
            }
        }
    }
    // At this point we have the only reference to the object
    if (new != NULL)
    {
        new->retainc = 1;
        // objects retain their pool so they can return to it
        // and/or use its destroy callback.
        FFGLPoolRetain(pool);
    }
    return new;
}

FFGLPoolObjectRef FFGLPoolObjectRetain(FFGLPoolObjectRef object)
{
    if (object)
        OSAtomicIncrement32Barrier(&object->retainc);
    return object;
}

void FFGLPoolObjectRelease(FFGLPoolObjectRef object)
{
    if (object)
    {
        if (OSAtomicDecrement32Barrier(&object->retainc) == 0)
        {
            FFGLPoolRef pool = object->pool;
            if (pool != NULL)
            {
                // lock pool for mutation
                OSSpinLockLock(&pool->lock);
                // check to see if the pool has space for us to return to it
                if (pool->level < pool->size)
                {
                    // get onto the top of the pool
                    // and incremement the level counter
                    pool->members[pool->level++] = object;
                    // unlock, mutation over
                    OSSpinLockUnlock(&pool->lock);
                }
                else
                {
                    // the pool didn't have room, so it's time to die
                    // we're not going to mutate the pool, so unlock
                    OSSpinLockUnlock(&pool->lock);
                    _FFGLPoolObjectDispose(object);
                }
                // objects don't retain the pool while they are in it,
                // otherwise it would never be released.
                FFGLPoolRelease(pool);
            }
        }
    }
}

static void _FFGLPoolObjectDispose(FFGLPoolObjectRef object)
{
    // this is called either from pool or object release
    // in either case, the pool is retained until this has returned
    if (object->pool->callbacks.destroy != NULL)
        object->pool->callbacks.destroy(object->object, object->pool->useri);
    free(object);
}

const void *FFGLPoolObjectGetData(FFGLPoolObjectRef object)
{
    return object->object;
}
