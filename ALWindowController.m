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
                         
                         if([buildStyle selectedSegment] == 0)
                         {
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
    NSLock* lock = [[NSRecursiveLock alloc] init];
    BOOL started = NO;
    cancel = NO;
    long long size;
    unsigned char* accumulator = nil;
    long long imageCount = 0, totalFrameCount = 0;
    int imageWidth, imageHeight;
    QTMovie* movie;
    QTTime movieEndTime, movieCurrentTime, movieStepTime;
    NSBitmapImageRep* lastImage = nil;
    NSMutableDictionary* movieAttributes;
    
    // extract data from the dictionary
    NSArray* files = [threadData objectForKey:@"files"];
    NSURL* folder = [threadData objectForKey:@"outputURL"];
    BOOL isVideo = [[threadData objectForKey:@"type"] isEqualToString:@"video"];
    BOOL buildAll = [[threadData objectForKey:@"buildStyle"] isEqualToString:@"all"];
    
    dispatch_queue_t dispatchQueue = dispatch_get_global_queue(0, 0);
    dispatch_group_t dispatchGroup = dispatch_group_create();
    
    if (isVideo) {
        // load the video
        [QTMovie enterQTKitOnThread];
        movie = [[QTMovie alloc] initWithFile:[[NSURL URLWithString:[files lastObject]] path] error:nil];
        [movie setAttribute:[NSNumber numberWithBool:NO] forKey:QTMovieLoopsAttribute];
        movieEndTime = [movie duration];
        [movie gotoBeginning];
        movieCurrentTime = [movie currentTime];
        [movie stepForward];
        movieStepTime = [movie currentTime];
        [movie gotoBeginning];
        
        if (movie == nil) {
            NSLog(@"Failed to load video.");
            [lock release];
            [release release];
            return;
        }
        
        totalFrameCount = movieEndTime.timeValue / movieStepTime.timeValue;
    }
    else {
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
            break;
        }
        [lock unlock];
        
        NSAutoreleasePool* innerReleasePool = [[NSAutoreleasePool alloc] init];
        unsigned char* bitmap;
        NSBitmapImageRep* image;
        
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
        
        if (image == nil) {
            NSLog(@"Skipped (couldn't load image).");
            continue;
        }
        
        if (started &&
            (imageWidth != [image pixelsWide] ||
             imageHeight != [image pixelsHigh])) {
            NSLog(@"Skipped (size doesn't match).");
            [image release];
            continue;
        }
        
        bitmap = [image bitmapData];
        
        // if this is the first image, initialize the arrays
        if (!started) {
            imageWidth = [image pixelsWide];
            imageHeight = [image pixelsHigh];
            size = imageWidth * imageHeight;
            
            // animate the size of the window
            [lock lock];
            
            NSRect rect = [[self window] frame];
            
            // save the origin size so that it can be restoed
            originalSize = rect;
            
            float width = fmin(DISPLAY_WIDTH, imageWidth);
            float height = width * ((float)imageHeight / imageWidth) +
                           rect.size.height - [imageView frame].size.height;
            
            if (height < [[self window] minSize].height) {
                width *= [[self window] minSize].height / height;
                height *= [[self window] minSize].height / height;
            }
            
            rect.origin.x += (rect.size.width - width) / 2;
            rect.origin.y += (rect.size.height - height) / 2;
            rect.size.width = width;
            rect.size.height = height;
            
            targetSize = rect;
            
            [self performSelectorOnMainThread:@selector(enlargeWindow) withObject:nil waitUntilDone:NO];
            
            [lock unlock];
            
            accumulator = (unsigned char*)calloc(size * 4, sizeof(unsigned char));
            
            memcpy(accumulator, bitmap, size * 4);
            
            started = YES;
        }
        else { // otherwise, average the images
            dispatch_apply(imageHeight, dispatchQueue, ^(size_t y){
                for (size_t i = (y * imageWidth * 4); i < (y * imageWidth * 4) + (imageWidth * 4); i++) {
                    // average this image's color with the previous colors
                    accumulator[i] = (accumulator[i] * imageCount + bitmap[i]) / (imageCount + 1);
                }
            });
            
            memcpy(bitmap, accumulator, size * 4);
        }
        
        imageCount++;
        
        if (buildAll) {
            dispatch_group_async(dispatchGroup, dispatchQueue, ^{
                NSData* saveData = [image representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
                NSString* outputFilename = [NSString stringWithFormat:@"Average Lapse Frame %i.jpg", imageCount];
                [saveData writeToURL:[folder URLByAppendingPathComponent:outputFilename] atomically:YES];
                [image release];
                
                // TODO: I think that the displayed picture might be wrong at some point
                // because we're doing this asynchronously. Do we care?
                [lock lock];
                [imageView setImage:[[[NSImage alloc] initWithData:saveData] autorelease]];
                [lock unlock];
            });
        }
        else {
            if (lastImage) {
                [lastImage release];
            }
            
            lastImage = image;
        }

        [innerReleasePool release];
    }
    
    if (lastImage) {
        // Build and output the last frame
        if (!buildAll) {
            NSData* saveData = [lastImage representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
            [saveData writeToURL:[folder URLByAppendingPathComponent:@"Average Lapse Final Frame.jpg"] atomically:YES];
        }
        
        [lastImage release];
    }
        
    if (accumulator) {
        free(accumulator);
    }
    
    if (isVideo) {
        [movie release];
    }
    
    [lock lock];
    if (!cancel) {
        [lock unlock];
        dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
    }
    else {
        [lock unlock];
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
                                   clickContext:nil];
    }
    
    [lock unlock];
    [lock release];
    [release release];
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
