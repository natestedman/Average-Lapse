//
//  ALProgressBar.m
//  AverageLapse
//
//  Created by Nate Stedman on 5/18/10.
//  Copyright 2010 Nate Stedman. All rights reserved.
//

#import "ALProgressBar.h"


@implementation ALProgressBar

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    
    NSRect rect = [self bounds];
    //rect.size.height--;
    
    NSRect progressRect = rect;
    progressRect.size.width *= (float)([self doubleValue] / [self maxValue]);
    progressRect.size.height -= 2;
    progressRect.origin.y += 1;
    
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                         xRadius:4
                                                         yRadius:4];
    
    NSBezierPath* progressPath = [NSBezierPath bezierPathWithRoundedRect:progressRect
                                                                 xRadius:4
                                                                 yRadius:4];
    
    NSGradient* grad;
    NSGradient* progressGrad;
    if( [[self window] isKeyWindow]) {
        grad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.204 alpha:1]
                                             endingColor:[NSColor colorWithCalibratedWhite:0.463 alpha:1]];
        
        progressGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.996 alpha:1]
                                                     endingColor:[NSColor colorWithCalibratedWhite:0.722 alpha:1]];
        
        [[NSColor colorWithCalibratedWhite:0.306 alpha:1] set];
    }
    else {
        grad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.996 alpha:1]
                                             endingColor:[NSColor colorWithCalibratedWhite:0.663 alpha:1]];
        
        progressGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.204 alpha:1]
                                                     endingColor:[NSColor colorWithCalibratedWhite:0.463 alpha:1]];
        
        [[NSColor colorWithCalibratedWhite:0.663 alpha:1] set];
    }    
    
    [grad drawInBezierPath:path angle:90];
    [progressGrad drawInBezierPath:progressPath angle:90];
    
    [[NSGraphicsContext currentContext] saveGraphicsState];
	[[NSGraphicsContext currentContext] setShouldAntialias: NO];
    
    [path stroke];
    
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    
    [grad release];
    [progressGrad release];
}

@end
