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

The views and conclusions contained in the software and documentation are those of the
authors and should not be interpreted as representing official policies, either expressed
or implied, of Nate Stedman.
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
                         
                         if (!testImage) {
                             if (![QTMovie canInitWithURL:url]) {
                                 NSLog(@"Unknown file type. Must be image or video.");
                             }
                             
                             NSLog(@"Rendering a movie");
                             QTMovie* movie = [[QTMovie alloc] initWithFile:[url path] error:nil];
                             [self performSelectorInBackground:@selector(threadMovie:)
                                                    withObject:[NSArray arrayWithObjects:movie, [[open URLs] objectAtIndex:0], nil]];
                         }
                         else {
                             [testImage release];
                             NSLog(@"Rendering an image series");
                             [self performSelectorInBackground:@selector(thread:)
                                                    withObject:[NSArray arrayWithObjects:files, [[open URLs] objectAtIndex:0], nil]];
                         }

                     }
                 }];
    
}

-(void)thread:(NSArray*)array {
    // set up
    NSAutoreleasePool* release = [[NSAutoreleasePool alloc] init];
    NSLock* lock = [[NSLock alloc] init];
    BOOL started = NO;
    int size;
    long long *r, *g, *b;
    int imageCount = 0;
    int imageWidth, imageHeight;
    
    // extract data from the array
    NSArray* files = [array objectAtIndex:0];
    NSURL* folder = [array objectAtIndex:1];
    
    [lock lock];
    [progressBar setMaxValue:[files count]];
    [lock unlock];
    
    for (int i = 0; i < [files count]; i++) {
        unsigned char* bitmap;
        NSData* data;
        NSBitmapImageRep* image;
        NSString* outputFilename;
        NSData* saveData;
        
        NSLog(@"%@", [files objectAtIndex:i]);
        
        // load the image
        data = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:[files objectAtIndex:i]]];
        image = [[NSBitmapImageRep alloc] initWithData:data];
        [data release];
        
        if (image == nil) {
            NSLog(@"Skipped (couldn't load image).");
            [lock lock];
            [progressBar setIntValue:i + 1];
            [lock unlock];
            continue;
        }
        
        if (started &&
            (imageWidth != [image pixelsWide] ||
             imageHeight != [image pixelsHigh])) {
            NSLog(@"Skipped (size doesn't match).");
            [lock lock];
            [progressBar setIntValue:i + 1];
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
            }
        }
        
        imageCount++;
        
        saveData = [image representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
        outputFilename = [NSString stringWithFormat:@"Average Lapse Frame %i.jpg", imageCount];
        [saveData writeToURL:[folder URLByAppendingPathComponent:outputFilename] atomically:YES];
        
        [lock lock];
        [progressBar setIntValue:i + 1];
        [imageView setImage:[[NSImage alloc] initWithData:saveData]];
        [lock unlock];
        
        [image release];
    }
    
    free(r);
    free(g);
    free(b);
    
    [lock release];
    [release release];
}

-(void)threadMovie:(NSArray*)array {
    // set up
    NSAutoreleasePool* release = [[NSAutoreleasePool alloc] init];
    NSLock* lock = [[NSLock alloc] init];
    BOOL started = NO;
    int size;
    double *r, *g, *b;
    int imageCount = 0;
    int i = 0;
    
    [QTMovie enterQTKitOnThread];
    
    // extract data from the array
    QTMovie* movie = [array objectAtIndex:0];
    [movie attachToCurrentThread];
    NSURL* folder = [array objectAtIndex:1];
    
    [lock lock];
    [progressBar setMaxValue:[movie duration].timeValue];
    [lock unlock];
    
    NSLog(@"%lld", [movie duration].timeValue);

    // TODO: fix time increment, etc.
    for (long long time = 0; time < [movie duration].timeValue; time += 1) {
        
        // get the frame's image
        NSImage* img = [movie frameImageAtTime:QTMakeTime(time, 1)];
        NSBitmapImageRep* image = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
        
        // if this is the first image, initialize the arrays
        if (!started) {
            size = [image pixelsHigh] * [image pixelsWide];
            r = (double*)malloc(sizeof(double) * size);
            g = (double*)malloc(sizeof(double) * size);
            b = (double*)malloc(sizeof(double) * size);
            
            for (int i = 0; i < size; i++) {
                NSColor* color = [image colorAtX:i % [image pixelsWide] y:i / [image pixelsWide]];
                r[i] = (double)[color redComponent];
                g[i] = (double)[color greenComponent];
                b[i] = (double)[color blueComponent];
            }
            started = YES;
        }
        
        // otherwise, average the images
        else {
            for (int i = 0; i < size; i++) {
                // average this images color with the previous colors
                NSColor* color = [image colorAtX:i % [image pixelsWide] y:i / [image pixelsWide]];
                r[i] = (r[i] * imageCount + (double)[color redComponent]) / (double)(imageCount + 1);
                g[i] = (g[i] * imageCount + (double)[color greenComponent]) / (double)(imageCount + 1);
                b[i] = (b[i] * imageCount + (double)[color blueComponent]) / (double)(imageCount + 1);
                
                // write the color back to the image, as we're done with this pixel
                [image setColor:[NSColor colorWithCalibratedRed:(float)r[i]
                                                          green:(float)g[i]
                                                           blue:(float)b[i]
                                                          alpha:1]
                            atX:i % [image pixelsWide]
                              y:i / [image pixelsWide]];
            }
        }
        
        imageCount++;
        
        NSData* save = [image representationUsingType:NSJPEGFileType properties:JPEG_PROPERTIES];
        [image release];
        
        NSString* str = [NSString stringWithFormat:@"Average Lapse Frame %i.jpg", i];
        
        [save writeToURL:[folder URLByAppendingPathComponent:str] atomically:YES];
        
        [lock lock];
        [progressBar setIntValue:time];
        [lock unlock];
        
        i++;
    }
    
    free(r);
    free(g);
    free(b);
    
    [QTMovie exitQTKitOnThread];
    [lock release];
    [release release];
}

@end
