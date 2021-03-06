//
//  FFGLQCPlugIn.m
//  FFGLQC
//
//  Created by Tom on 12/10/2009.
//  Copyright (c) 2009 Tom Butterworth. All rights reserved.
//

/* It's highly recommended to use CGL macros instead of changing the current context for plug-ins that perform OpenGL rendering */

#import <OpenGL/CGLMacro.h>

#import "FFGLQCPlugIn.h"
#import <pthread.h>

#define	kQCPlugIn_Name				@"FreeFrame Plugin"
#define	kQCPlugIn_Description		@"Use FreeFrame Plugins in Quartz Composer."


static void FFImageUnlockQCInput(GLuint name, CGLContextObj cgl_ctx, void *userInfo)
{
	[(id <QCPlugInInputImageSource>)userInfo unlockTextureRepresentation];
}

static void FFImageUnlockAndReleaseFFGLTexture(CGLContextObj cgl_ctx, GLuint name, void* context)
{
    [(FFGLImage *)context unlockTextureRectRepresentation];
    [(FFGLImage *)context release];
}

@implementation FFGLQCPlugIn

@dynamic outputImage, outputInfo;

+ (NSDictionary*) attributes
{
	/*
	Return a dictionary of attributes describing the plug-in (QCPlugInAttributeNameKey, QCPlugInAttributeDescriptionKey...).
	*/
	
	return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey, kQCPlugIn_Description, QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
	/*
	Specify the optional attributes for property based ports (QCPortAttributeNameKey, QCPortAttributeDefaultValueKey...).
	*/
	if ([key isEqualToString:@"outputImage"])
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
	if ([key isEqualToString:@"outputInfo"])
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Plugin Properties", QCPortAttributeNameKey, nil];
	return nil;
}

+ (NSArray *)sortedPropertyPortKeys
{
	return [NSArray arrayWithObjects:@"outputImage", @"outputInfo", nil];
}

+ (QCPlugInExecutionMode) executionMode
{
	/*
	Return the execution mode of the plug-in: kQCPlugInExecutionModeProvider, kQCPlugInExecutionModeProcessor, or kQCPlugInExecutionModeConsumer.
	*/
	
	return kQCPlugInExecutionModeProcessor;
}

+ (QCPlugInTimeMode) timeMode
{
	/*
	Return the time dependency mode of the plug-in: kQCPlugInTimeModeNone, kQCPlugInTimeModeIdle or kQCPlugInTimeModeTimeBase.
	*/
	
	return kQCPlugInTimeModeTimeBase;
}

- (id) init
{
	if(self = [super init]) {
		/*
		Allocate any permanent resource required by the plug-in.
		*/
            if (pthread_mutex_init(&_lock, NULL) != 0) {
                [self release];
                return nil;
            }
	}
	
	return self;
}

- (void) finalize
{
	/*
	Release any non garbage collected resources created in -init.
	*/
    pthread_mutex_destroy(&_lock);
	[super finalize];
}

- (void) dealloc
{
	/*
	Release any resources created in -init.
	*/
    pthread_mutex_destroy(&_lock);
    [_plugins release];
    [_plugin release];
    [_renderer release];
    [super dealloc];
}

+ (NSArray*) plugInKeys
{
	/*
	Return a list of the KVC keys corresponding to the internal settings of the plug-in.
	*/
    return [NSArray arrayWithObject:@"plugin"];
}

- (id) serializedValueForKey:(NSString*)key;
{
	/*
	Provide custom serialization for the plug-in internal settings that are not values complying to the <NSCoding> protocol.
	The return object must be nil or a PList compatible i.e. NSString, NSNumber, NSDate, NSData, NSArray or NSDictionary.
	*/
	if ([key isEqualToString:@"plugin"])
	{
		NSDictionary *attributes = [[_renderer plugin] attributes];
		NSString *path = [attributes objectForKey:FFGLPluginAttributePathKey];
		NSString *identifier = [attributes objectForKey:FFGLPluginAttributeIdentifierKey];
		return [NSDictionary dictionaryWithObjectsAndKeys:path, @"FFGLQCPluginPath", identifier, @"FFGLQCPluginIdentifier", nil];
	}
	else
	{
		return [super serializedValueForKey:key];
	}
}

- (void) setSerializedValue:(id)serializedValue forKey:(NSString*)key
{
	/*
	Provide deserialization for the plug-in internal settings that were custom serialized in -serializedValueForKey.
	Deserialize the value, then call [self setValue:value forKey:key] to set the corresponding internal setting of the plug-in instance to that deserialized value.
	*/
	if ([key isEqualToString:@"plugin"])
	{
		FFGLPlugin *plugin;
		NSString *path = [(NSDictionary *)serializedValue objectForKey:@"FFGLQCPluginPath"];
		if (path != nil)
		{
			plugin = [[[FFGLPlugin alloc] initWithPath:path] autorelease];
			if (plugin == nil)
			{
				NSString *identifier = [(NSDictionary *)serializedValue objectForKey:@"FFGLQCPluginIdentifier"];
				if (identifier != nil)
				{
					NSArray *plugins = [self plugins];
					FFGLPlugin *next;
					for (next in plugins) {
						if ([[[next attributes] objectForKey:FFGLPluginAttributeIdentifierKey] isEqualToString:identifier])
						{
							plugin = next;
							break;
						}
					}
				}
			}
		}
		else
		{
			plugin = nil;
		}
		[self setPlugin:plugin];
	}
	else
	{
		[super setSerializedValue:serializedValue forKey:key];
	}
}

- (QCPlugInViewController*) createViewController
{
	/*
	Return a new QCPlugInViewController to edit the internal settings of this plug-in instance.
	You can return a subclass of QCPlugInViewController if necessary.
	*/
	
	return [[QCPlugInViewController alloc] initWithPlugIn:self viewNibName:@"Settings"];
}

- (FFGLPlugin *)plugin
{
    return _plugin;
}

- (void)setPlugin:(FFGLPlugin *)plugin
{
    [plugin retain];
    pthread_mutex_lock(&_lock);
    if ([_plugin type] == FFGLPluginTypeSource) {
        [self removeInputPortForKey:@"inputWidth"];
        [self removeInputPortForKey:@"inputHeight"];
    }
    NSArray *keys = [_plugin parameterKeys];
    NSString *key;
    for (key in keys) {
        [self removeInputPortForKey:key];
    }
    [_plugin release];
    _plugin = plugin;
    if ([plugin type] == FFGLPluginTypeSource) {
        [self addInputPortWithType:QCPortTypeIndex forKey:@"inputWidth"
                    withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:@"Width", QCPortAttributeNameKey,
									[NSNumber numberWithUnsignedInt:640], QCPortAttributeDefaultValueKey, nil]];
        [self addInputPortWithType:QCPortTypeIndex forKey:@"inputHeight"
                    withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:@"Height", QCPortAttributeNameKey, 
									[NSNumber numberWithUnsignedInt:480], QCPortAttributeDefaultValueKey, nil]];
    }
    keys = [_plugin parameterKeys];
		
    for (key in keys)
	{
        NSDictionary *attributes = [_plugin attributesForParameterWithKey:key];
        NSMutableDictionary *portAttributes = [NSMutableDictionary dictionaryWithCapacity:3];
        NSString *type = [attributes objectForKey:FFGLParameterAttributeTypeKey];
        NSString *name = [attributes objectForKey:FFGLParameterAttributeNameKey];
        [portAttributes setObject:name forKey:QCPortAttributeNameKey];
        NSNumber *defaultValue = [attributes objectForKey:FFGLParameterAttributeDefaultValueKey];
        if (defaultValue != nil) {
            [portAttributes setObject:defaultValue forKey:QCPortAttributeDefaultValueKey];
        }
		if ([type isEqualToString:FFGLParameterTypeImage])
		{
			[portAttributes setObject:name forKey:QCPortAttributeNameKey];
			[self addInputPortWithType:QCPortTypeImage forKey:key
						withAttributes:portAttributes];
		}
		
		if ([type isEqualToString:FFGLParameterTypeBoolean] || [type isEqualToString:FFGLParameterTypeEvent]) {
            [self addInputPortWithType:QCPortTypeBoolean forKey:key
                        withAttributes:portAttributes];
        } else if ([type isEqualToString:FFGLParameterTypeNumber]) {
            [portAttributes setObject:[NSNumber numberWithFloat:0.0] forKey:QCPortAttributeMinimumValueKey];
            [portAttributes setObject:[NSNumber numberWithFloat:1.0] forKey:QCPortAttributeMaximumValueKey];
            [self addInputPortWithType:QCPortTypeNumber forKey:key withAttributes:portAttributes];
        } else if ([type isEqualToString:FFGLParameterTypeString]) {
            [self addInputPortWithType:QCPortTypeString forKey:key withAttributes:portAttributes];
        }
    }
    self.rendererNeedsRebuild = YES;
    pthread_mutex_unlock(&_lock);
}

@synthesize rendererNeedsRebuild = _rendererNeedsRebuild;

- (NSArray *)plugins {
    @synchronized(self) {
        if (_plugins == nil) {
            _plugins = [[NSMutableArray alloc] initWithCapacity:10];
            NSArray *all = [[FFGLPluginManager sharedManager] plugins];
            FFGLPlugin *next;
            for (next in all) {
                if ([next mode] == FFGLPluginModeGPU) {
                    [_plugins addObject:next];
                } else {
#if __BIG_ENDIAN__
                    NSString *pixelFormat = FFGLPixelFormatARGB8888;
#else
                    NSString *pixelFormat = FFGLPixelFormatBGRA8888;
#endif
                    if ([[next supportedBufferPixelFormats] containsObject:pixelFormat]) {
                        [_plugins addObject:next];
                    }
                }
            }
        }
    }
    return _plugins;
}
@end

@implementation FFGLQCPlugIn (Execution)

- (BOOL) startExecution:(id<QCPlugInContext>)context
{
	/*
	Called by Quartz Composer when rendering of the composition starts: perform any required setup for the plug-in.
	Return NO in case of fatal failure (this will prevent rendering of the composition to start).
	*/
    self.rendererNeedsRebuild = YES;
    _cspace = CGColorSpaceRetain([context colorSpace]);
    return YES;
}

- (void) enableExecution:(id<QCPlugInContext>)context
{
	/*
	Called by Quartz Composer when the plug-in instance starts being used by Quartz Composer.
	*/
}

- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary*)arguments
{
	/*
	Called by Quartz Composer whenever the plug-in instance needs to execute.
	Only read from the plug-in inputs and produce a result (by writing to the plug-in outputs or rendering to the destination OpenGL context) within that method and nowhere else.
	Return NO in case of failure during the execution (this will prevent rendering of the current frame to complete).
	
	The OpenGL context for rendering can be accessed and defined for CGL macros using:
	CGLContextObj cgl_ctx = [context CGLContextObj];
	*/
    
#if __BIG_ENDIAN__
    NSString *qcPixelFormat = QCPlugInPixelFormatARGB8;
    NSString *ffPixelFormat = FFGLPixelFormatARGB8888;
#else
    NSString *qcPixelFormat = QCPlugInPixelFormatBGRA8;
    NSString *ffPixelFormat = FFGLPixelFormatBGRA8888;
#endif
    
    CGLContextObj cgl_ctx = [context CGLContextObj];
	CGLLockContext(cgl_ctx);
	
    pthread_mutex_lock(&_lock);
    FFGLPlugin *plugin = self.plugin;
    NSArray *keys = [plugin parameterKeys];
    // If our input dimensions changed (for a source plugin) then we need to rebuild the renderer.
    if ([plugin type] == FFGLPluginTypeSource)
    {
        if ([self didValueForInputKeyChange:@"inputWidth"] || [self didValueForInputKeyChange:@"inputHeight"])
	{
            _dimensions.width = [[self valueForInputKey:@"inputWidth"] floatValue];
            _dimensions.height = [[self valueForInputKey:@"inputHeight"] floatValue];
             self.rendererNeedsRebuild = YES;
         }
    } 
    else 
    {
        NSString *key;
        // If our first input image changed shape we need to rebuild the renderer because effect renderers base their dimensions on this
        for (key in keys)
	{
            if ([self didValueForInputKeyChange:key]
                && [[[plugin attributesForParameterWithKey:key] objectForKey:FFGLParameterAttributeTypeKey] isEqualToString:FFGLParameterTypeImage])
	    {
                id <QCPlugInInputImageSource> input = [self valueForInputKey:key];
                NSRect inputBounds = [input imageBounds];
                if (_dimensions.width != inputBounds.size.width || _dimensions.height != inputBounds.size.height) 
				{
                    self.rendererNeedsRebuild = YES;
                    _dimensions.width = inputBounds.size.width;
                    _dimensions.height = inputBounds.size.height;
                }
                break; // we base our dimensions on the size of our first image input.
            }
        }
    }
    BOOL needsAllInputs;
    if (self.rendererNeedsRebuild)
    {
        [_renderer release];
	// FFGLRendererHintTextureRect asks the renderer to output rect textures directly (if it can) and saves a 2D to Rect conversion stage.
		if (self.plugin && cgl_ctx)
		{
			_renderer = [[FFGLRenderer alloc] initWithPlugin:self.plugin context:cgl_ctx pixelFormat:ffPixelFormat outputHint:FFGLRendererHintTextureRect size:_dimensions];
		}
        self.rendererNeedsRebuild = NO;
		self.outputInfo = [self.plugin attributes];
        needsAllInputs = YES;
    }
    else
    {
        needsAllInputs = NO;
    }
    
    NSString *key;
	NSMutableArray *imageInputs = [NSMutableArray arrayWithCapacity:4];
    for (key in keys)
    {
		if ([[[plugin attributesForParameterWithKey:key] objectForKey:FFGLParameterAttributeTypeKey] isEqualToString:FFGLParameterTypeImage])
		{
			// We need to set image inputs every time we render, as we set them to nil after rendering to avoid keeping textures around
			[imageInputs addObject:key];
			id <QCPlugInInputImageSource> input = [self valueForInputKey:key];
			
			// Just now VVFFGL doesn't support scaling images, and CPU renderers don't support mis-matched inputs, so...
			if ((_renderer.plugin.mode == FFGLPluginModeGPU)
				|| (([input imageBounds].size.width == _renderer.size.width) && ([input imageBounds].size.height == _renderer.size.height)))
			{
				FFGLImage *image;
				// prep the QC images texture for being turned into a FFGL image.
				// our FFImageUnlockQCInput callback will unlock for us.
				if(input && [input lockTextureRepresentationWithColorSpace:_cspace forBounds:[input imageBounds]])
				{	
					
					//NSLog(@"have QCimage for key %@ and locked rep", key);
									
					
					//NSLog(@"new FFGL based on rect texture: %u", [input textureName]);
					
					
					image = [[FFGLImage alloc] initWithTextureRect:[input textureName]
														CGLContext:cgl_ctx
														pixelsWide:[input imageBounds].size.width
														pixelsHigh:[input imageBounds].size.height
														   flipped:[input textureFlipped]
												   releaseCallback:FFImageUnlockQCInput
													   releaseInfo:input];
				}
				else
				{
					image = nil;
				}
				[_renderer setValue:image forParameterKey:key];
				[image release];
			}
		}
		else if (needsAllInputs || [self didValueForInputKeyChange:key])
		{
			[_renderer setValue:[self valueForInputKey:key] forParameterKey:key];
		}
    }
	BOOL result;
    FFGLImage *output;
    if (output = [_renderer createOutputAtTime:time])
    {		
        id <QCPlugInOutputImageProvider> provider;
        if ([output lockTextureRectRepresentation])
		{
            provider = [context outputImageProviderFromTextureWithPixelFormat:qcPixelFormat 
                                                                   pixelsWide:[output imagePixelsWide]
                                                                   pixelsHigh:[output imagePixelsHigh]
                                                                         name:[output textureRectName]
                                                                      flipped:NO
                                                              releaseCallback:FFImageUnlockAndReleaseFFGLTexture
                                                               releaseContext:output
                                                                   colorSpace:_cspace
                                                             shouldColorMatch:YES];
            self.outputImage = provider;
            result = YES;
        }
		else
		{
            result = YES;
			self.outputImage = nil;
        }
    } 
    else
    {
        result = YES;
		self.outputImage = nil;
    }
	for (key in imageInputs)
	{
		[_renderer setValue:nil forParameterKey:key];
	}
    pthread_mutex_unlock(&_lock);
	CGLUnlockContext(cgl_ctx);
	return result;
}

- (void) disableExecution:(id<QCPlugInContext>)context
{
//	NSLog(@"called disable Execution");
	/*
	Called by Quartz Composer when the plug-in instance stops being used by Quartz Composer.
	*/
}

- (void) stopExecution:(id<QCPlugInContext>)context
{
//	NSLog(@"called stop Execution");

	/*
	Called by Quartz Composer when rendering of the composition stops: perform any required cleanup for the plug-in.
	*/
    CGColorSpaceRelease(_cspace);
    [_renderer release];
    _renderer = nil;
}

@end
