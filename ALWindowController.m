/*
Copyright 2010 Nate Stedman. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list
of conditions and the following disclaimer in the documentation and/or other materials
provided with the distribution.

THIS SOFTWARE IS PROVIDED BY NATE STEDMAN ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL NATE STEDMAN OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <math.h>
#import <QTKit/QTKit.h>
#import <Growl/Growl.h>
#import "ALWindowController.h"

#define JPEG_KEYS [NSArray arrayWithObjects:NSImageCompressionFactor, nil]
#define JPEG_OBJECTS [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.9f], nil]
#define JPEG_PROPERTIES [NSDictionary dictionaryWithObjects:JPEG_OBJECTS forKeys:JPEG_KEYS]
#define DISPLAY_WIDTH 800

@implementation ALWindowController

-(void)awakeFromNib {
    [dropView setFrame:[mainView frame]];   
    [mainView setSubviews:[NSArray arrayWithObject:dropView]];
}

-(void)generate:(NSArray*)files {
    // ask the user for an output folder
    NSOpenPanel* open = [[NSOpenPanel alloc] init];
    [open setCanChooseFiles:NO];
    [open setCanChooseDirectories:YES];
    [open setAllowsMultipleSelection:NO];
    [open setCanCreateDirectories:YES];
    [open setPrompt:@"Render"];
    [open setTitle:@"Select an output directory"];
    
    // raise the window
    [NSApp activateIgnoringOtherApps:YES];
    
    // run the sheet
    [open beginSheetModalForWindow:[self window]
                 completionHandler:^(NSInteger result) {
                     if (result == NSFileHandlingPanelOKButton) {
                         [progressBar setDoubleValue:0];
                         [progressBar displayIfNeeded];
                         
                         NSURL* url = [NSURL URLWithString:[files objectAtIndex:0]];
                         NSImage* testImage = [[NSImage alloc] initWithContentsOfURL:url];
                         NSMutableDictionary* threadData = [[[NSMutableDictionary alloc] init] autorelease];
                         
                         [threadData setObject:files forKey:@"files"];
                         [threadData setObject:[[open URLs] lastObject] forKey:@"outputURL"];
                         
                         if([buildStyle selectedSegment] == 0) {
                             [threadData setObject:@"all" forKey:@"buildStyle"];
                         }
                         else {
                             [threadData setObject:@"last" forKey:@"buildStyle"];
                         }
                         
                         if (!testImage) {
                             if (![QTMovie canInitWithURL:url]) {
                                 NSAlert *error = [[[NSAlert alloc] init] autorelease];
                                 [error addButtonWithTitle:@"OK"];
                                 [error setMessageText:@"Unknown file type."];
                                 [error setInformativeText:@"Must be image or video."];
                                 [error setAlertStyle:NSWarningAlertStyle];
                                 [error runModal];
                                 
                                 return;
                             }
                             
                             NSLog(@"Rendering a movie");
                             [threadData setObject:@"video" forKey:@"type"];
                             
                             [self performSelectorInBackground:@selector(thread:)
                                                    withObject:threadData];
                         }
                         else {
                             [testImage release];
                             
                             NSLog(@"Rendering an image series");
                             [threadData setObject:@"image" forKey:@"type"];
                             
                             [self performSelectorInBackground:@selector(thread:)
                                                    withObject:threadData];
                         }
                         
                         [progressView setFrame:[mainView frame]];
                         [mainView setSubviews:[NSArray arrayWithObject:progressView]];

                     }
                 }];
    
}

-(void)thread:(NSDictionary*)threadData {
    NSAutoreleasePool* release = [[NSAutoreleasePool alloc] init];
    lock = [[NSRecursiveLock alloc] init];
    BOOL started = NO;
    cancel = NO;
    long long size;
    unsigned char* accumulator = nil;
    long long imageCount = 0, totalFrameCount = 0;
    int imageWidth, imageHeight;
    QTMovie* movie;
    QTTime movieCurrentTime, movieStepTime;
    NSBitmapImageRep* previousImage = nil;
    NSMutableDictionary* movieAttributes;
    NSMutableArray* failedFrames = [[NSMutableArray alloc] init];
    
    // extract data from the dictionary
    NSArray* files = [threadData objectForKey:@"files"];
    NSURL* folder = [threadData objectForKey:@"outputURL"];
    BOOL isVideo = [[threadData objectForKey:@"type"] isEqualToString:@"video"];
    BOOL buildAll = [[threadData objectForKey:@"buildStyle"] isEqualToString:@"all"];
    
    dispatch_queue_t dispatchQueue = dispatch_get_global_queue(0, 0);
    
    if (isVideo) {
        // load the video
        // TODO: support averaging multiple videos?
        [QTMovie enterQTKitOnThread];
        NSString* moviePath = [[NSURL URLWithString:[files lastObject]] path];
        movie = [[QTMovie alloc] initWithFile:moviePath error:nil];
        
        // disable looping, in case the video was created with that enabled
        [movie setAttribute:[NSNumber numberWithBool:NO] forKey:QTMovieLoopsAttribute];
        
        // determine the timestep of one frame; this is a hack and will fail
        // silently for any video with a dynamic framerate
        [movie gotoBeginning];
        movieCurrentTime = [movie currentTime];
        [movie stepForward];
        movieStepTime = [movie currentTime];
        
        // start at the first frame of the movie
        [movie gotoBeginning];
        
        if (movie == nil) {
            // TODO: We shouldn't just *die* here
            [failedFrames addObject:[[[NSDictionary alloc] initWithObjectsAndKeys:moviePath,@"file",@"Failed to load video.",@"message"] autorelease]];
            [lock release];
            [release release];
            return;
        }
        
        // estimate the total number of frames, based on the timestep we
        // calculated before and the total duration of the movie; this will
        // fail like the timestep calculation on movies with dynamic framerates
        totalFrameCount = [movie duration].timeValue / movieStepTime.timeValue;
    }
    else {
        // the number of frames with an image sequence is the number of files
        totalFrameCount = [files count];
    }
    
    [lock lock];
    [progressBar setMaxValue:totalFrameCount];
    [lock unlock];
    
    movieAttributes = [NSMutableDictionary dictionary];
    [movieAttributes setObject:QTMovieFrameImageTypeNSImage forKey:QTMovieFrameImageType];
    
    for (long long frame = 0; frame < totalFrameCount; frame++) {
        [lock lock];
        if (cancel) {
            [lock unlock];
            break;
        }
        [lock unlock];
        
        NSAutoreleasePool* innerReleasePool;
        unsigned char* bitmap;
        NSBitmapImageRep* image;
        NSString* errorPath;
        
        // create an autorelease pool for the inner loop; this is necessary
        // primarily to cleanup after various automatically autoreleased objects
        // which otherwise very quickly consume a great deal of memory
        innerReleasePool = [[NSAutoreleasePool alloc] init];
        
        [lock lock];
        [progressBar setDoubleValue:frame];
        [progressBar displayIfNeeded];
        [lock unlock];
        
        // load the frame, either from the video or from the file
        if (isVideo) {
            NSImage* img = [movie frameImageAtTime:movieCurrentTime withAttributes:movieAttributes error:nil];
            image = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
            movieCurrentTime.timeValue += movieStepTime.timeValue;
        }
        else {
            NSData* data = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:[files objectAtIndex:frame]]];
            image = [[NSBitmapImageRep alloc] initWithData:data];
            [data release];
        }
        
        if (isVideo) {
            errorPath = [[NSURL URLWithString:[files lastObject]] path];
        }
        else {
            errorPath = [[NSURL URLWithString:[files objectAtIndex:frame]] path];
        }
        
        if (image == nil) {
            [failedFrames addObject:[[[NSDictionary alloc] initWithObjectsAndKeys:errorPath,@"file",@"Failed to load image.",@"message"] autorelease]];
            continue;
        }
        
        if (started &&
            (imageWidth != [image pixelsWide] ||
             imageHeight != [image pixelsHigh])) {
            [failedFrames addObject:[[[NSDictionary alloc] initWithObjectsAndKeys:errorPath,@"file",@"Image size doesn't match first frame.",@"message"] autorelease]];
            [image release];
            continue;
        }
        
        bitmap = [image bitmapData];
        
        if (!started) {
            // if this is the first image, initialize various data structures
            imageWidth = [image pixelsWide];
            imageHeight = [image pixelsHigh];
            size = imageWidth * imageHeight;
            
            [self resizeWindowToFitImage:image];
            
            // create the running average accumulator buffer
            accumulator = (unsigned char*)calloc(size * 4, sizeof(unsigned char));
            
            // copy the first frame directly into the accumulator buffer
            memcpy(accumulator, bitmap, size * 4);
            
            started = YES;
        }
        else {
            // average the images, dispatching a block for each row
            dispatch_apply(imageHeight, dispatchQueue, ^(size_t y){
                // add our row of the current image into the running average
                for (size_t i = (y * imageWidth * 4); i < ((y + 1) * imageWidth * 4); i++) {
                    accumulator[i] = (accumulator[i] * imageCount + bitmap[i]) / (imageCount + 1);
                }
            });
            
            // copy the current running average into the output bitmap
            memcpy(bitmap, accumulator, size * 4);
        }
        
        imageCount++;
        
        if (buildAll) {
            // output the current frame of the accumulator buffer to disk
            NSData* saveData = [image representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
            NSString* outputFilename = [NSString stringWithFormat:@"Average Lapse Frame %i.jpg", imageCount];
            [saveData writeToURL:[folder URLByAppendingPathComponent:outputFilename] atomically:YES];
            [image release];
            
            [lock lock];
            [imageView setImage:[[[NSImage alloc] initWithData:saveData] autorelease]];
            [lock unlock];
        }
        else {
            if (previousImage) {
                [previousImage release];
            }
            
            previousImage = image;
        }

        [innerReleasePool release];
    }
    
    if (!buildAll && previousImage) {
        // build and output the last frame, if we're only building one frame
        NSData* saveData = [previousImage representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
        [saveData writeToURL:[folder URLByAppendingPathComponent:@"Average Lapse Final Frame.jpg"] atomically:YES];
        [previousImage release];
    }
        
    if (accumulator) {
        free(accumulator);
    }
    
    if (isVideo) {
        [movie release];
    }
    
    if (!cancel) {
        if ([failedFrames count]) {
            [self showFailedFramesDialog:[failedFrames retain]];
        }
    }
    
    [lock lock];
    [imageView setImage:nil];
    [dropView setFrame:[mainView frame]];
    [mainView setSubviews:[NSArray arrayWithObject:dropView]];
    [self performSelectorOnMainThread:@selector(restoreWindow) withObject:nil waitUntilDone:NO];
    
    if (!cancel) {
        NSSound* sound = [NSSound soundNamed:@"Glass"];
        [sound play];
        
        // post a Growl notification
        [GrowlApplicationBridge notifyWithTitle:@"Rendering Complete"
                                    description:[folder path]
                               notificationName:@"Rendering Complete"
                                       iconData:nil
                                       priority:0
                                       isSticky:NO
                                   clickContext:[folder path]];
    }
    
    [lock unlock];
    [lock release];
    [failedFrames release];
    [release release];
}

-(void)showFailedFramesDialog:(NSArray*)failedFrames {
    errorView.failedFrames = failedFrames;
    
    NSAlert *error = [[[NSAlert alloc] init] autorelease];
    [error addButtonWithTitle:@"OK"];
    [error setMessageText:@"Some frames failed to render."];
    // TODO: someone besides me needs to write some words (render? load? runon? help!)
    [error setInformativeText:@"The following frames failed to render; this could be caused by corrupt files or images of differing sizes."];
    [error setAlertStyle:NSWarningAlertStyle];
    [error setAccessoryView:errorView];
    [error beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
                        contextInfo:nil];
}

-(void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [[alert window] orderOut:self];
}

-(void)resizeWindowToFitImage:(NSBitmapImageRep*)image {
    [lock lock];
    
    NSRect rect;
    int imageWidth, imageHeight;
    
    imageWidth = [image pixelsWide];
    imageHeight = [image pixelsHigh];
    rect = [[self window] frame];
    
    // save the origin size so that it can be restored later
    originalSize = rect;
    
    float width = fmin(DISPLAY_WIDTH, imageWidth);
    float height = width * ((float)imageHeight / imageWidth) +
        rect.size.height - [imageView frame].size.height;
    
    if (height < [[self window] minSize].height) {
        width *= [[self window] minSize].height / height;
        height *= [[self window] minSize].height / height;
    }
    
    // adjust new window frame to resize outward from the current center
    rect.origin.x += (rect.size.width - width) / 2;
    rect.origin.y += (rect.size.height - height) / 2;
    rect.size.width = width;
    rect.size.height = height;
    
    targetSize = rect;
    
    [self performSelectorOnMainThread:@selector(enlargeWindow) withObject:nil waitUntilDone:NO];
    
    [lock unlock];
}

-(void)enlargeWindow {
    [[self window] setFrame:targetSize display:YES animate:YES];
}

-(void)restoreWindow {
    // restore the original size, but zoom down to the center of the window    
    NSRect rect = [[self window] frame];
    rect.origin.x += (rect.size.width - originalSize.size.width) / 2;
    rect.origin.y += (rect.size.height - originalSize.size.height) / 2;
    rect.size.width = originalSize.size.width;
    rect.size.height = originalSize.size.height;
    
    [[self window] setFrame:rect display:YES animate:YES];
}

-(IBAction)cancelAction:(id)sender {
    cancel = YES;
}

@end
