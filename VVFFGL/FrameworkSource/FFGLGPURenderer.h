//
//  FFGLGPURenderer.h
//  VVOpenSource
//
//  Created by Tom on 10/08/2009.
//

#import <Cocoa/Cocoa.h>
#import "FFGLRenderer.h"
#import "FFGLInternal.h"
#import <OpenGL/OpenGL.h>
#import "FFGLPool.h"

//typedef struct FFGLGPURendererTexInfo FFGLGPURendererTexInfo;

@interface FFGLGPURenderer : FFGLRenderer {
@private
//	FFGLGPURendererTexInfo *_textureInfo;
    FFGLProcessGLStruct _frameStruct;

    GLenum _textureTarget;
    GLuint _rendererFBO;		// this FBO is responsible for providing the GL_TEXTURE_2D texture that FFGL requires.
    GLuint _rendererDepthBuffer;	// depth buffer
    NSUInteger _textureWidth;
    NSUInteger _textureHeight;
	FFGLPoolRef _pool;
	//	GLuint _rendererFBOTexture;	// COLOR_ATTACHMENT_0 for our above FBO
}

@end
