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

#import "ALDragView.h"


@implementation ALDragView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
}

#pragma mark -
#pragma mark Dragging

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    return NSDragOperationGeneric;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    return NSDragOperationGeneric;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard* board = [sender draggingPasteboard];
    
    // make an array for the files
    NSMutableArray* files = [[[NSMutableArray alloc] initWithCapacity:[[board pasteboardItems] count]] autorelease];
    
    // get all of the filenames
    for (NSPasteboardItem* item in [board pasteboardItems]) {
        [files addObject:[item stringForType:@"public.file-url"]];
    }
    
    // sort the files
    [files sortUsingSelector:@selector(compare:)];
    
    // start generating the average lapse
    [windowController generate:files];
    
    return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender {
    
}

@end
