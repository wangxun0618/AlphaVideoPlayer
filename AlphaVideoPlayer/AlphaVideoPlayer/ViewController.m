//
//  ViewController.m
//  AlphaVideoPlayer
//
//  Created by M2-2023 on 2025/6/26.
//

#import "ViewController.h"
#import "WXAlphaVideoPlayer.h"

@interface ViewController ()

@property (nonatomic, strong)WXAlphaVideoPlayer *player;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    
    self.player = [[WXAlphaVideoPlayer alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.player];
    self.player.loopEnabled = YES;
    NSString *file = [NSBundle.mainBundle pathForResource:@"qpdx_2" ofType:@".mp4"];
    
    [self.player playWithURL:[NSURL fileURLWithPath:file] placeholderImage:nil enableAlphaMask:YES maskDirection:WXAlphaMaskDirectionLeftToRight];
    
    
    
}


@end
