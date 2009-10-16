//
//  FFGLCPURenderer.m
//  VVOpenSource
//
//  Created by Tom on 10/08/2009.
//

#import "FFGLCPURenderer.h"
//#import "FFGLRendererSubclassing.h"
#import "FFGLImage.h"
#import <QuartzCore/QuartzCore.h>

static void FFGLCPURendererBufferRelease(const void *baseAddress, void* context) {
    // for now, just free the buffer, could make them reusable, or use a CVPixelBufferPool
    free((void *)baseAddress);
}

@implementation FFGLCPURenderer

- (id)initWithPlugin:(FFGLPlugin *)plugin pixelFormat:(NSString *)format forBounds:(NSRect)bounds
{
    if (self = [super initWithPlugin:plugin pixelFormat:format forBounds:bounds]) {
        NSUInteger numBuffers = [plugin _maximumInputFrameCount];
        if (numBuffers > 0) {
            _buffers = malloc(sizeof(void *) * numBuffers);
            if (_buffers == NULL) {
                [self release];
                return nil;
            }
        }
        _fcStruct.inputFrameCount = numBuffers;
        _fcStruct.inputFrames = _buffers;
#if __BIG_ENDIAN__
        if ([format isEqualToString:FFGLPixelFormatRGB565]) { _bpp = 2; }
        else if ([format isEqualToString:FFGLPixelFormatRGB888]) { _bpp = 3; }
        else if ([format isEqualToString:FFGLPixelFormatARGB8888]) { _bpp = 4; }
#else
        if ([format isEqualToString:FFGLPixelFormatBGR565]) { _bpp = 2; }
        else if ([format isEqualToString:FFGLPixelFormatBGR888]) { _bpp = 3; }
        else if ([format isEqualToString:FFGLPixelFormatBGRA8888]) { _bpp = 4; }
#endif
        else { // This should never happen, as it is checked in FFGLRenderer at init.
            [NSException raise:@"FFGLRendererException" format:@"Unexpected pixel format."];
        }
    }
    return self;
}

- (void)dealloc
{
    if (_buffers != NULL)
        free(_buffers);
    [super dealloc];
}

- (BOOL)_implementationSetImage:(id)image forInputAtIndex:(NSUInteger)index
{
    if ([image lockBufferRepresentationWithPixelFormat:[self pixelFormat]]) {
        if (([image bufferPixelsHigh] != [self bounds].size.height) || ([image bufferPixelsWide] != [self bounds].size.width)
            || ([image bufferPixelFormat] != [self pixelFormat])) {
            [image unlockBufferRepresentation];
            // Not sure what we do here - for now raise exception, could just return NO.
            // But that failure is only used within FFGLRenderer, not transmitted to client.
            [NSException raise:@"FFGLRendererException" format:@"Input image dimensions or format do not match renderer."];
            return NO;
        }
        _buffers[index] = (void *)[image bufferBaseAddress];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_implementationRender
{
    // We could cache the values of [self plugin], [self bounds], [self _instance] and [self pixelFormat]
    // at init, as they are constant for our lifetime.
    FFGLPlugin *plugin = [self plugin];
    NSRect bounds = [self bounds];
    BOOL result;
    _fcStruct.outputFrame = valloc(bounds.size.width * _bpp * bounds.size.height);
    if (_fcStruct.outputFrame == NULL) {
        return NO;
    }
    if ([plugin _prefersFrameCopy]) {
        result = [plugin _processFrameCopy:&_fcStruct forInstance:[self _instance]];
    } else {
        if (_fcStruct.inputFrameCount > 0) { // ie we are not a source
            memcpy(_fcStruct.outputFrame, _buffers[0], bounds.size.width * _bpp * bounds.size.height);
        }
        result = [plugin _processFrameInPlace:_fcStruct.outputFrame forInstance:[self _instance]];
    }
    FFGLImage *output;
    if (result) {
        output = [[[FFGLImage alloc] initWithBuffer:_fcStruct.outputFrame
                                         CGLContext:NULL // TODO:
                                        pixelFormat:[self pixelFormat]
                                         pixelsWide:bounds.size.width
                                         pixelsHigh:bounds.size.height
                                        bytesPerRow:bounds.size.width * _bpp
                                    releaseCallback:FFGLCPURendererBufferRelease
                                        releaseInfo:NULL] autorelease];
    } else {
        free(_fcStruct.outputFrame);
        output = nil;
    }
    [self setOutputImage:output];
    return result;
}

@end
