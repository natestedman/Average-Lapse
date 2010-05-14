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

#import <QTKit/QTKit.h>
#import "ALWindowController.h"

#define JPEG_KEYS [NSArray arrayWithObjects:NSImageCompressionFactor, nil]
#define JPEG_OBJECTS [NSArray arrayWithObjects:[NSNumber numberWithFloat:1.0f], nil]
#define JPEG_PROPERTIES [NSDictionary dictionaryWithObjects:JPEG_OBJECTS forKeys:JPEG_KEYS]

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
                         [progressView setFrame:[mainView frame]];
                         [mainView setSubviews:[NSArray arrayWithObject:progressView]];
                         
                         NSURL* url = [NSURL URLWithString:[files objectAtIndex:0]];
                         NSImage* testImage = [[NSImage alloc] initWithContentsOfURL:url];
                         NSMutableDictionary* threadData = [[[NSMutableDictionary alloc] init] autorelease];
                         
                         [threadData setObject:files forKey:@"files"];
                         [threadData setObject:[[open URLs] lastObject] forKey:@"outputURL"];
                         
                         if (!testImage) {
                             if (![QTMovie canInitWithURL:url]) {
                                 NSLog(@"Unknown file type. Must be image or video.");
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

                     }
                 }];
    
}

-(void)thread:(NSDictionary*)threadData {
    NSAutoreleasePool* release = [[NSAutoreleasePool alloc] init];
    NSLock* lock = [[NSLock alloc] init];
    BOOL started = NO;
    int size;
    long long* accumulator = nil;
    int imageCount = 0, totalFrameCount = 0;
    int imageWidth, imageHeight;
    QTMovie* movie;
    
    // extract data from the dictionary
    NSArray* files = [threadData objectForKey:@"files"];
    NSURL* folder = [threadData objectForKey:@"outputURL"];
    BOOL isVideo = [[threadData objectForKey:@"type"] isEqualToString:@"video"];
    
    dispatch_queue_t q_default = dispatch_get_global_queue(0, 0);
    
    if (isVideo) {
        // load the video
        [QTMovie enterQTKitOnThread];
        movie = [[QTMovie alloc] initWithFile:[[NSURL URLWithString:[files lastObject]] path] error:nil];
        
        if (movie == nil) {
            NSLog(@"Failed to load video.");
            [lock release];
            [release release];
            return;
        }
        
        totalFrameCount = [movie duration].timeValue;
    }
    else {
        totalFrameCount = [files count];
    }
    
    [lock lock];
    [progressBar setMaxValue:totalFrameCount];
    [lock unlock];
    
    for (int frame = 0; frame < totalFrameCount; frame++) {
        unsigned char* bitmap;
        NSBitmapImageRep* image;
        
        [lock lock];
        [progressBar setIntValue:frame];
        [lock unlock];
        
        if (!isVideo) {
            NSLog(@"%@", [files objectAtIndex:frame]);
        }
        
        // load the frame, either from the video or from the file
        if (isVideo) {
            NSImage * img = [movie frameImageAtTime:QTMakeTime(frame, [movie duration].timeScale)];
            image = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
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
            
            accumulator = (long long*)calloc(size * 4, sizeof(long long));
            
            #pragma omp parallel for shared(r, g, b, bitmap)
            for (int i = 0; i < size * 4; i++) {
                accumulator[i] = bitmap[i];
            }
            started = YES;
        }
        else { // otherwise, average the images
            #pragma omp parallel for shared(r, g, b, bitmap)
            for (int i = 0; i < size * 4; i++) {
                // average this image's color with the previous colors
                bitmap[i] = accumulator[i] = (accumulator[i] * imageCount + bitmap[i]) / (imageCount + 1);
            }
        }
        
        imageCount++;
        
        dispatch_async(q_default, ^{
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
    
    if (accumulator) {
        free(accumulator);
    }
    
    if (isVideo) {
        [movie release];
    }
    
    [lock lock];
    [progressBar setIntValue:[progressBar maxValue]];
    [lock unlock];
    
    [lock release];
    [release release];
}

@end
