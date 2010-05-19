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

-(void)setDoubleValue:(double)doubleValue {
    [super setDoubleValue:doubleValue];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    
    NSRect rect = [self bounds];
    rect.size.height--;
    
    NSBezierPath* borderPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5)
                                                         xRadius:4
                                                         yRadius:4];
    rect.origin.y--;
    NSBezierPath* lightPath = [NSBezierPath bezierPathWithRoundedRect:rect
                                                              xRadius:4
                                                              yRadius:4];
    rect.origin.y++;
    
    rect = NSInsetRect(rect, 1, 1);
    
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                         xRadius:2
                                                         yRadius:2];
    rect.size.width *= (float)([self doubleValue] / [self maxValue]);
    
    NSBezierPath* progressPath = [NSBezierPath bezierPathWithRoundedRect:rect
                                                                 xRadius:3
                                                                 yRadius:3];
    
    NSGradient* grad;
    NSGradient* progressGrad;
    NSColor* fillColor;
    
    if ([[self window] isKeyWindow]) {
        grad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithDeviceWhite:0.204 alpha:1]
                                             endingColor:[NSColor colorWithDeviceWhite:0.463 alpha:1]];
        
        progressGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithDeviceWhite:0.996 alpha:1]
                                                     endingColor:[NSColor colorWithDeviceWhite:0.722 alpha:1]];
        
        [[NSColor colorWithDeviceWhite:0.729 alpha:1] set];
        fillColor = [NSColor colorWithDeviceWhite:0.306 alpha:1];
    }
    else {
        grad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithDeviceWhite:0.357 alpha:1]
                                             endingColor:[NSColor colorWithDeviceWhite:0.624 alpha:1]];
        
        progressGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithDeviceWhite:0.996 alpha:1]
                                                     endingColor:[NSColor colorWithDeviceWhite:0.820 alpha:1]];
        
        [[NSColor colorWithDeviceWhite:0.882 alpha:1] set];
        fillColor = [NSColor colorWithDeviceWhite:0.663 alpha:1];
    }
    
    [[NSGraphicsContext currentContext] saveGraphicsState];
	[[NSGraphicsContext currentContext] setShouldAntialias: YES];
    
    // draw the highlight
    [lightPath stroke];
    [lightPath fill];
    
    // draw the outline
    [fillColor set];
    [borderPath stroke];
    [borderPath fill];
    
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    
    [grad drawInBezierPath:path angle:90];
    
    if (rect.size.width > 0.0) {
        [progressGrad drawInBezierPath:progressPath angle:90];
    }
    
    [grad release];
    [progressGrad release];
}

@end
