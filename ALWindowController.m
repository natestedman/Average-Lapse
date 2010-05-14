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
                             
                             //QTMovie* movie = [[QTMovie alloc] initWithFile:[url path] error:nil];
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
    // set up
    NSAutoreleasePool* release = [[NSAutoreleasePool alloc] init];
    NSLock* lock = [[NSLock alloc] init];
    BOOL started = NO;
    int size;
    long long *r = nil, *g = nil, *b = nil;
    int imageCount = 0, totalFrameCount = 0;
    int imageWidth, imageHeight;
    
    // extract data from the array
    NSArray* files = [threadData objectForKey:@"files"];
    NSURL* folder = [threadData objectForKey:@"outputURL"];
    BOOL isVideo = [[threadData objectForKey:@"type"] isEqualToString:@"video"];
    QTMovie* movie;
    
    if (isVideo) {
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
        NSString* outputFilename;
        NSData* saveData;
        
        if (!isVideo) {
            NSLog(@"%@", [files objectAtIndex:frame]);
        }
        
        // load the image
        if (isVideo) {
            NSImage * img = [movie frameImageAtTime:QTMakeTime(frame, [movie duration].timeScale)];
            image = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
            //[img release];
        }
        else {
            NSData* data = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:[files objectAtIndex:frame]]];
            image = [[NSBitmapImageRep alloc] initWithData:data];
            [data release];
        }
        
        if (image == nil) {
            NSLog(@"Skipped (couldn't load image).");
            [lock lock];
            [progressBar setIntValue:frame + 1];
            [lock unlock];
            continue;
        }
        
        if (started &&
            (imageWidth != [image pixelsWide] ||
             imageHeight != [image pixelsHigh])) {
            NSLog(@"Skipped (size doesn't match).");
            [lock lock];
            [progressBar setIntValue:frame + 1];
            [lock unlock];
            [image release];
            continue;
        }
        
        bitmap = [image bitmapData];
        
        // if this is the first image, initialize the arrays
        if (!started) {
            imageWidth = [image pixelsWide];
            imageHeight = [image pixelsHigh];
            size = imageWidth * imageHeight;
            
            r = (long long*)malloc(sizeof(long long) * size);
            g = (long long*)malloc(sizeof(long long) * size);
            b = (long long*)malloc(sizeof(long long) * size);
            
            #pragma omp parallel for
            for (int i = 0; i < size; i++) {
                r[i] = bitmap[(i * 4) + 0];
                g[i] = bitmap[(i * 4) + 1];
                b[i] = bitmap[(i * 4) + 2];
            }
            started = YES;
        }
        else { // otherwise, average the images
            #pragma omp parallel for
            for (int i = 0; i < size; i++) {
                // average this image's color with the previous colors
                r[i] = (r[i] * imageCount + bitmap[(i * 4) + 0]) / (imageCount + 1);
                g[i] = (g[i] * imageCount + bitmap[(i * 4) + 1]) / (imageCount + 1);
                b[i] = (b[i] * imageCount + bitmap[(i * 4) + 2]) / (imageCount + 1);
                
                // write the color back to the image, as we're done with this pixel
                bitmap[(i * 4) + 0] = r[i];
                bitmap[(i * 4) + 1] = g[i];
                bitmap[(i * 4) + 2] = b[i];
                
                if(i % imageWidth == 0) {
                    [lock lock];
                    [progressBar setDoubleValue:frame + ((double)i / (double)size)];
                    [lock unlock];
                }
            }
        }
        
        imageCount++;
        
        saveData = [image representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
        outputFilename = [NSString stringWithFormat:@"Average Lapse Frame %i.jpg", imageCount];
        [saveData writeToURL:[folder URLByAppendingPathComponent:outputFilename] atomically:YES];
        
        [lock lock];
        [progressBar setIntValue:frame + 1];
        [imageView setImage:[[[NSImage alloc] initWithData:saveData] autorelease]];
        [lock unlock];
        
        [image release];
    }
    
    if (r != nil) {
        free(r);
    }
    if (g != nil) {
        free(g);
    }
    if (b != nil) {
        free(b);
    }
    
    [lock release];
    [release release];
    
    if (isVideo) {
        [movie release];
    }
}

@end
