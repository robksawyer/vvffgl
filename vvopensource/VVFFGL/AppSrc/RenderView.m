//
//  RenderView.m
//  VVOpenSource
//
//  Created by Tom on 22/09/2009.
//  Copyright 2009 Tom Butterworth. All rights reserved.
//

#import "RenderView.h"
#import <QuartzCore/QuartzCore.h>

@implementation RenderView
- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
    if (self = [super initWithFrame:frameRect pixelFormat:format]) {

    }
    return self;
}

- (void)dealloc
{
    CGColorSpaceRelease(_cspace);
    [_ciContext release];
    [super dealloc];
}

@synthesize renderChain = _chain;

- (void)prepareOpenGL {
    _cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    _ciContext = [[CIContext contextWithCGLContext:[[self openGLContext] CGLContextObj]
                                       pixelFormat:cglPixelFormat
                                           options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                    (id)_cspace,kCIContextOutputColorSpace,
                                                    (id)_cspace,kCIContextWorkingColorSpace,nil]] retain];
    _needsReshape = YES;
}

- (void)reshape {
    _needsReshape = YES;
    [super reshape];
}

- (void)update {
    [super update];
}

- (void)drawRect:(NSRect)dirtyRect
{
	CGLContextObj cgl_ctx = [[self openGLContext] CGLContextObj];
	CGLLockContext(cgl_ctx);
    
	if(_needsReshape)
    {
        NSRect		frame = [self frame];
        NSRect		bounds = [self bounds];
        GLfloat 	minX, minY, maxX, maxY;
            
        minX = NSMinX(bounds);
        minY = NSMinY(bounds);
        maxX = NSMaxX(bounds);
        maxY = NSMaxY(bounds);
            
        [self update];
            
        if(NSIsEmptyRect([self visibleRect])) 
        {
            glViewport(0, 0, 1, 1);
        } else {
            glViewport(0, 0,  frame.size.width ,frame.size.height);
        }
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(minX, maxX, maxY, minY, -1.0, 1.0);
       
		glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
		
		
        glClearColor(0.0, 0.0, 0.0, 0.0);
            
        glClear(GL_COLOR_BUFFER_BIT);
        _needsReshape = NO;
    }
    FFGLImage *image = [_chain output];
    if ([image lockTexture2DRepresentation])
	{
        // draw it
		glColor4f(1.0, 1.0, 1.0, 1.0);
		
		NSLog(@"Attempting to draw texture: %u,  width: %u, height %u", [image texture2DName], [image texture2DPixelsWide], [image texture2DPixelsHigh]);
		
		glActiveTexture(GL_TEXTURE0);
		glEnable(GL_TEXTURE_2D);
		glBindTexture(GL_TEXTURE_2D, [image texture2DName]);
	
		glDisable(GL_BLEND);
	//	glEnable(GL_BLEND);
	//	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		
		glBegin(GL_QUADS);
		glTexCoord2i(0, 0);
		glVertex2i(0, 0);
		glTexCoord2i(0, 1);
		glVertex2i(0, [image texture2DPixelsHigh]);
		glTexCoord2i(1, 1);
		glVertex2i([image texture2DPixelsWide], [image texture2DPixelsHigh]);
		glTexCoord2i(1, 0);
		glVertex2i([image texture2DPixelsWide], 0);
		glEnd();		
		

	} 
	else if ([image lockBufferRepresentationWithPixelFormat:FFGLPixelFormatBGRA8888]) { // This won't be needed once FFGLImage can convert buffers->textures
        NSUInteger bpr = [image bufferBytesPerRow];
        NSUInteger w = [image bufferPixelsWide];
        NSUInteger h = [image bufferPixelsHigh];
        
        NSData *data = [NSData dataWithBytesNoCopy:[image bufferBaseAddress] length:h * bpr freeWhenDone:NO];
        CIImage *ci = [CIImage imageWithBitmapData:data
                                       bytesPerRow:bpr
                                              size:CGSizeMake(w, h)
                                            format:kCIFormatARGB8 // wrong way around but fuck it
                                        colorSpace:_cspace];
//        CIImage *ci = [CIImage imageWithColor:[CIColor colorWithRed:0.0 green:0.0 blue:1.0]];
        CGPoint at = CGPointMake(([self bounds].size.width / 2) - (w / 2), ([self bounds].size.height / 2) - ( h / 2));
        [_ciContext drawImage:ci atPoint:at fromRect:[ci extent]];
    } else if (image != nil) {
        NSLog(@"lockBufferRepresentationWithPixelFormat failed");
    } else {
        glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(GL_COLOR_BUFFER_BIT);
    }
 
	CGLFlushDrawable(cgl_ctx);	
	CGLUnlockContext(cgl_ctx);
}

@end
