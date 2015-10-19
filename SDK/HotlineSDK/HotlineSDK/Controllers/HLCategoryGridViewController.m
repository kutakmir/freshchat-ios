//
//  HLCollectionView.m
//  HotlineSDK
//
//  Created by kirthikas on 22/09/15.
//  Copyright © 2015 Freshdesk. All rights reserved.
//

#import "HLCategoryGridViewController.h"
#import "HLGridViewCell.h"
#import "HLContainerController.h"
#import "HLArticlesController.h"
#import "KonotorDataManager.h"
#import "HLFAQServices.h"
#import "HLMacros.h"
#import "HLArticlesController.h"
#import "FDLocalNotification.h"
#import "HLCategory.h"
#import "FDSolutionUpdater.h"
#import "HLTheme.h"

@interface HLCategoryGridViewController () <UIScrollViewDelegate>

@property (nonatomic,strong) NSArray *categories;

@end

@implementation HLCategoryGridViewController

-(void)willMoveToParentViewController:(UIViewController *)parent{
    parent.title = HLLocalizedString(@"FAQ_TITLE_TEXT");
    self.view.backgroundColor = [UIColor whiteColor];
    [self updateCategories];
    [self setupCollectionView];
    [self setNavigationItem];
    [self localNotificationSubscription];
}

-(void) viewWillAppear:(BOOL)animated{
    [self fetchUpdates];    
}

-(void)setNavigationItem{
    UIImage *searchButtonImage = [HLTheme getImageFromMHBundleWithName:HLLocalizedString(@"FAQ_GRID_VIEW_SEARCH_BUTTON_IMAGE")];

    UIBarButtonItem *searchButton = [[UIBarButtonItem alloc] initWithImage:searchButtonImage style:UIBarButtonItemStylePlain target:self action:@selector(searchButtonAction:)];

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc]initWithTitle:HLLocalizedString(@"FAQ_GRID_VIEW_CLOSE_BUTTON_TITLE_TEXT") style:UIBarButtonItemStylePlain target:self action:@selector(closeButton:)];
    
    self.parentViewController.navigationItem.leftBarButtonItem = closeButton;
    self.parentViewController.navigationItem.rightBarButtonItem = searchButton;
}

-(void)searchButtonAction:(id)sender{
    NSLog(@"Launch");
}

-(void)updateCategories{
    [[KonotorDataManager sharedInstance]fetchAllSolutions:^(NSArray *solutions, NSError *error) {
        if (!error) {
            self.categories = solutions;
            [self.collectionView reloadData];
        }
    }];
}

-(void)fetchUpdates{
    FDSolutionUpdater *updater = [[FDSolutionUpdater alloc]init];
    [[KonotorDataManager sharedInstance]areSolutionsEmpty:^(BOOL isEmpty) {
        if(isEmpty){
            [updater resetTime];
        }
        [updater fetch];
    }];
}

-(void)closeButton:(id)sender{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)localNotificationSubscription{
    __weak typeof(self)weakSelf = self;
    [[NSNotificationCenter defaultCenter]addObserverForName:HOTLINE_SOLUTIONS_UPDATED object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.categories = @[];
            [weakSelf updateCategories];
            NSLog(@"Got Notifications");
        });
    }];
}

-(void)setupCollectionView{
    
    UICollectionViewFlowLayout* flowLayout = [[UICollectionViewFlowLayout alloc]init];
    self.collectionView = [[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flowLayout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.collectionView];
    
    NSDictionary *views = @{ @"collectionView" : self.collectionView};
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[collectionView]|"
                                                                      options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[collectionView]|" options:0 metrics:nil views:views]];
    
    
    //Collection view subclass
    [self.collectionView registerClass:[HLGridViewCell class] forCellWithReuseIdentifier:@"FAQ_GRID_CELL"];
}

#pragma mark - Collection view delegat0e

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView{
    return 1;
}

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{
    if(!self.categories){
        return 0;
    }
    return [self.categories count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HLGridViewCell *cell = [self.collectionView dequeueReusableCellWithReuseIdentifier:@"FAQ_GRID_CELL" forIndexPath:indexPath];
    if (!cell) {
        cell = [[HLGridViewCell alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width/2, [UIScreen mainScreen].bounds.size.width/2 )];
    }
    if (self.categories.count > 0){
            HLCategory *category = (self.categories)[indexPath.row];
            cell.label.text = category.title;
            cell.label.numberOfLines =0;
            cell.layer.borderWidth=0.0f;
            cell.layer.borderColor=[UIColor grayColor].CGColor;
            // Only load cached images; defer new downloads until scrolling ends
            if (!category.icon){
                cell.imageView.image=[UIImage imageNamed:@"loading.png"];
            }else{
                cell.imageView.image = [UIImage imageWithData:category.icon];
                [cell.label sizeToFit];
            }
        }
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath{
    if (IS_IPAD) {
        return CGSizeMake( ([UIScreen mainScreen].bounds.size.width/3), ([UIScreen mainScreen].bounds.size.width/4));
    }
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
        return CGSizeMake( ([UIScreen mainScreen].bounds.size.width/3), ([UIScreen mainScreen].bounds.size.height/2));
    }
    return CGSizeMake( ([UIScreen mainScreen].bounds.size.width/2), ([UIScreen mainScreen].bounds.size.height/4));
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath{
    if (self.categories.count > 0) {
        HLCategory *category = self.categories[indexPath.row];
        HLArticlesController *articleController = [[HLArticlesController alloc] initWithCategory:category];
        HLContainerController *container = [[HLContainerController alloc]initWithController:articleController];
        [self.navigationController pushViewController:container animated:YES];
    }
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 0.0f;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
        return 0.0f;
}

// Layout: Set Edges
- (UIEdgeInsets)collectionView:
(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(0,0,0,0);  // top, left, bottom, right
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
    [self.collectionView reloadData];
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
