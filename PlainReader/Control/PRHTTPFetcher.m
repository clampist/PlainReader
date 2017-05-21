//
//  PRHTMLFetcher.m
//  PlainReader
//
//  Created by guojiubo on 14-3-24.
//  Copyright (c) 2014年 guojiubo. All rights reserved.
//

#import "PRHTTPFetcher.h"
#import "PRArticleParser.h"
#import "TFHppleElement+PRAdditions.h"
#import "PRTopCommentCell.h"
#import "PRDatabase.h"
#import "PRTopComment.h"

NSString *const PRHTTPFetcherDidFetchCommentsNotification = @"PRHTTPFetcherDidFetchCommentsNotification";

static NSString *const PRHTTPFetcherErrorDomain = @"PRHTTPFetcherErrorDomain";

static NSString *CBHomePageToken = nil;

@interface PRHTTPFetcher ()

@end

@implementation PRHTTPFetcher

#pragma mark - Helpers

- (AFHTTPSessionManager * )jsonSessionManager
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    // fixed server text/html issue
    NSSet *acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", @"text/plain", @"text/html", nil];
    [manager.responseSerializer setAcceptableContentTypes:acceptableContentTypes];
    return manager;
}

- (AFHTTPSessionManager *)httpSessionManager
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    return manager;
}

- (NSError *)parametersError
{
    return [NSError cw_errorWithDomain:PRHTTPFetcherErrorDomain code:-1024 message:@"Parameter Error"];
}

- (NSError *)serverError
{
    return [NSError cw_errorWithDomain:PRHTTPFetcherErrorDomain code:-1023 message:@"Bad Server Response"];
}

- (void)safelyCallback:(CWHTTPFetcherBlock)block
{
//    DDLogInfo(@"%@", [(NSURLSessionDataTask *)self.requestOperation responseString]);

    if (!block) {
        return;
    }
    
    if (self.error) {
        if ([self.error code] == NSURLErrorCancelled) {
            return;
        }
        
//        if ([self.requestOperation isKindOfClass:[AFHTTPRequestOperation class]]) {
//            AFHTTPRequestOperation *operation = (AFHTTPRequestOperation *)self.requestOperation;
//            DDLogError(@"%@\n%@", self.error, [operation responseString]);
//        }
    }
    
    if ([NSThread isMainThread]) {
        block(self, self.error);
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        block(self, self.error);
    });
}

- (NSString *)articleIDFromLink:(NSString *)link
{
    if (!link) {
        return nil;
    }
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"/(\\d*)\\." options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [reg firstMatchInString:link options:0 range:NSMakeRange(0, link.length)];
    if (match.numberOfRanges > 0) {
        return [link substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

- (NSString *)articleCategoryFromLink:(NSString *)link
{
    if (!link) {
        return nil;
    }
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"/(\\w+)/\\d+" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [reg firstMatchInString:link options:0 range:NSMakeRange(0, link.length)];
    if (match.numberOfRanges > 0) {
        return [link substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

- (NSString *)CommentCountFromText:(NSString *)text
{
    if (!text) {
        return nil;
    }
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [reg firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match.numberOfRanges > 0) {
        return [text substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

- (NSString *)cookiePHPSESSID
{
    NSHTTPCookieStorage *cs = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cs cookies]) {
        if ([[cookie name] isEqualToString:@"PHPSESSID"]) {
            return [cookie value];
        }
    }
    return nil;
}

- (NSString *)cookieCSRF_TOKEN
{
    NSHTTPCookieStorage *cs = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cs cookies]) {
        if ([[cookie name] isEqualToString:@"_csrf"]) {
            return [cookie value];
        }
    }
    return nil;
}

#pragma mark - APIs

- (void)fetchHomePage:(CWHTTPFetcherBlock)block
{
    AFHTTPSessionManager *manager = [self httpSessionManager];
    [manager GET:@"http://www.cnbeta.com" parameters:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TFHpple *hpple = [[TFHpple alloc] initWithHTMLData:responseObject];
            NSArray *items = [hpple searchWithXPathQuery:@"//div[@class=\"items-area\"]//div[@class=\"item\"]"];
            if ([items count] == 0) {
                self.error = [self serverError];
                [self safelyCallback:block];
                return;
            }
            
            // TOKEN
            NSString *wholeHTML = [[NSString alloc] initWithData:hpple.data encoding:NSUTF8StringEncoding];
            if (wholeHTML) {
                NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"csrf-token\" content=\"([^\"]*)\"" options:NSRegularExpressionCaseInsensitive error:nil];
                NSTextCheckingResult *match = [reg firstMatchInString:wholeHTML options:0  range:NSMakeRange(0, wholeHTML.length)];
                if (match.numberOfRanges > 0) {
                    CBHomePageToken = [wholeHTML substringWithRange:[match rangeAtIndex:1]];
                }
            }
            
            for (TFHppleElement *element in items) {
                PRArticle *article = [[PRArticle alloc] init];
                NSString *articleURL = [[element findFirstSubnodeWithTagName:@"a" ] objectForKey:@"href"];
                NSString *articleIdString = [[articleURL componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                NSArray<NSString *> *categoryArray = [articleURL componentsSeparatedByString:@"/"];
                article.category = [categoryArray objectAtIndex:[categoryArray count] - 2];
                article.articleId = @([articleIdString integerValue]);
                article.title = [[element findFirstSubnodeWithTagName:@"a"] text];
                NSString *articleStatus = [[[element findFirstSubnodeWithClassName:@"status"] findFirstSubnodeWithTagName:@"li"] text];
                NSString *pubTime = [[[articleStatus componentsSeparatedByString:@"|"] objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *prefixToRemove = @"发布于";
                if ([pubTime hasPrefix:prefixToRemove])
                    article.pubTime = [pubTime substringFromIndex:[prefixToRemove length]];
                NSString *commentCountString = [[articleStatus componentsSeparatedByString:@"|"] objectAtIndex:2];
                commentCountString = [[commentCountString componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                article.commentCount = @([commentCountString integerValue]);
                article.thumb = [[element findFirstSubnodeWithClassName:@"lazy"] objectForKey:@"src"];
                
                [[PRDatabase sharedDatabase] storeArticle:article];
            }
            
            [self safelyCallback:block];
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchRealtimeWithPage:(NSUInteger)page done:(CWHTTPFetcherBlock)block
{
    if (!CBHomePageToken) {
        self.error = [self parametersError];
        [self safelyCallback:block];
        return;
    }
    
    page = MAX(2, page);
    
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[@"_csrf"] = CBHomePageToken;
    parameters[@"type"] = @"all";
    parameters[@"page"] = @(page);
    int64_t time = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    parameters[@"_"] = @(time);
    
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"http://www.cnbeta.com/" forHTTPHeaderField:@"Referer"];

    [manager GET:@"http://www.cnbeta.com/home/more" parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *json = responseObject;
            if (![json[@"state"] isEqualToString:@"success"]) {
                self.error = [self serverError];
                [self safelyCallback:block];
                
                return;
            }
            
            NSArray *list = json[@"result"][@"list"];
            for (NSDictionary *dict in list) {
                PRArticle *article = [[PRArticle alloc] init];
                article.articleId = dict[@"sid"];
                article.title = dict[@"title"];
                article.category = dict[@"label"][@"class"];
                article.commentCount = dict[@"comments"];
                article.pubTime = dict[@"inputtime"];
                article.thumb = dict[@"thumb"];
                
                [[PRDatabase sharedDatabase] storeArticle:article];
            }
            
            [self safelyCallback:block];
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchWeekly:(CWHTTPFetcherBlock)block
{
    AFHTTPSessionManager *manager = [self httpSessionManager];
    [manager GET:@"http://www.cnbeta.com/top10.htm" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TFHpple *hpple = [[TFHpple alloc] initWithHTMLData:responseObject];
            NSArray *modules = [hpple searchWithXPathQuery:@"//div[@class=\"items-area rank-list\"]"];
            
            if (modules.count != 2) {
                self.error = [self serverError];
                [self safelyCallback:block];
                return;
            }
            
            [[PRDatabase sharedDatabase] clearWeekly];
            
            // 热门点击
            TFHppleElement *module = modules[0];
            NSArray *lis = [module childrenWithClassName:@"item"];
            for (TFHppleElement *element in lis) {
                NSData *recommendData = [[element raw] dataUsingEncoding:NSUTF8StringEncoding];
                TFHpple *recommendHpple = [[TFHpple alloc] initWithHTMLData:recommendData];
                
                TFHppleElement *aNode = [[recommendHpple searchWithXPathQuery:@"//a"] firstObject];
                NSString *link = [aNode objectForKey:@"href"];
                NSString *aidString = [self articleIDFromLink:link];
                NSString *category = [self articleCategoryFromLink:link];
                if (aidString) {
                    PRArticle *article = [[PRArticle alloc] init];
                    article.articleId = @([aidString integerValue]);
                    article.category = category;
                    article.title = aNode.text;
                    article.thumb = [[[recommendHpple searchWithXPathQuery:@"//img"] firstObject] objectForKey:@"src"];
                    TFHppleElement *label = [[recommendHpple searchWithXPathQuery:@"//label"] firstObject];
                    article.pubTime = label.text;
                    TFHppleElement *status = [[recommendHpple searchWithXPathQuery:@"//li"] lastObject];
                    article.commentCount = @([[self CommentCountFromText:status.text] integerValue]);
                    
                    [[PRDatabase sharedDatabase] storeArticle:article weeklyType:PRWeeklyTypeRecommend];
                }
            }
            
            // 热门评论
            module = modules[1];
            lis = [module childrenWithClassName:@"item"];
            for (TFHppleElement *element in lis) {
                NSData *hotCommentData = [[element raw] dataUsingEncoding:NSUTF8StringEncoding];
                TFHpple *hotCommentHpple = [[TFHpple alloc] initWithHTMLData:hotCommentData];
                
                TFHppleElement *aNode = [[hotCommentHpple searchWithXPathQuery:@"//a"] firstObject];
                NSString *link = [aNode objectForKey:@"href"];
                NSString *aidString = [self articleIDFromLink:link];
                NSString *category = [self articleCategoryFromLink:link];
                if (aidString) {
                    PRArticle *article = [[PRArticle alloc] init];
                    article.articleId = @([aidString integerValue]);
                    article.category = category;
                    article.title = aNode.text;
                    article.thumb = [[[hotCommentHpple searchWithXPathQuery:@"//img"] firstObject] objectForKey:@"src"];
                    TFHppleElement *label = [[hotCommentHpple searchWithXPathQuery:@"//label"] firstObject];
                    article.pubTime = label.text;
                    TFHppleElement *status = [[hotCommentHpple searchWithXPathQuery:@"//li"] lastObject];
                    article.commentCount = @([[self CommentCountFromText:status.text] integerValue]);
                    
                    [[PRDatabase sharedDatabase] storeArticle:article weeklyType:PRWeeklyTypeHot];
                }
            }
            
            [self safelyCallback:block];
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchArticle:(NSNumber *)articleId useCache:(BOOL)useCache done:(CWHTTPFetcherBlock)block;
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        PRArticle *article = [[PRDatabase sharedDatabase] articleForId:articleId];
        self.responseObject = article;

        if (useCache && article.content) {
            [self safelyCallback:block];
            return;
        }
        
        NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", article.category, articleId];
        AFHTTPSessionManager *manager = [self httpSessionManager];
        [manager GET:api parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                TFHpple *hpple = [[TFHpple alloc] initWithHTMLData:responseObject];
                [PRArticleParser parseArticle:article hpple:hpple];
                article.cacheStatus = @(PRArticleCacheStatusCached);
                [[PRDatabase sharedDatabase] storeArticle:article];
                
                [self safelyCallback:block];
            });
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            self.error = error;
            [self safelyCallback:block];
        }];
    });
}

- (void)fetchTopCommentsWithPage:(NSUInteger)page done:(CWHTTPFetcherBlock)block
{
    NSString *api = [NSString stringWithFormat:@"http://m.cnbeta.com/commentshow/p%lu.htm", (unsigned long)page];
    AFHTTPSessionManager *manager = [self httpSessionManager];
    [manager GET:api parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TFHpple *hpple = [[TFHpple alloc] initWithHTMLData:responseObject];
            NSArray *commentElements = [hpple searchWithXPathQuery:@"//ul[@class=\"module_list\"]/li"];
            if ([commentElements count] == 0) {
                self.error = [self serverError];
                [self safelyCallback:block];
                return;
            }
            
            if (page == 1) {
                [[PRDatabase sharedDatabase] clearTopComments];
            }
            
            for (TFHppleElement *commentElement in commentElements) {
                NSData *commentData = [[commentElement raw] dataUsingEncoding:NSUTF8StringEncoding];
                TFHpple *commentHpple = [[TFHpple alloc] initWithHTMLData:commentData];
                
                PRTopComment *comment = [[PRTopComment alloc] init];
                comment.content = [(TFHppleElement *)[[commentHpple searchWithXPathQuery:@"//div[@class=\"jh_title jh_text\"]/a"] firstObject] text];
                comment.from = [(TFHppleElement *)[[commentHpple searchWithXPathQuery:@"//strong"] firstObject] text];
                
                TFHppleElement *aNode = [[commentHpple searchWithXPathQuery:@"//a"] lastObject];
                PRArticle *article = [[PRArticle alloc] init];
                NSString *href = [aNode objectForKey:@"href"];
                NSString *aid = [self articleIDFromLink:href];
                NSString *category = [self articleCategoryFromLink:href];
                if (aid) {
                    article.articleId = @([aid integerValue]);
                }
                article.category = category;
                article.title = [aNode text];
                [[PRDatabase sharedDatabase] storeArticle:article];
                
                comment.article = article;
                [[PRDatabase sharedDatabase] storeTopComment:comment];
            }
            
            [self safelyCallback:block];
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchCommentsOfArticle:(PRArticle *)article done:(CWHTTPFetcherBlock)block
{
    NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/comment/read"];
    NSString *op = [NSString stringWithFormat:@"1,%@,%@", article.articleId, article.sn];
    
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[@"_csrf"] = article.csrf_token;
    parameters[@"op"] = op;
    
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *phpsession = [self cookiePHPSESSID];
    NSString *token = [self cookieCSRF_TOKEN];
    if (phpsession && token) {
        [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    }
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];

    [manager GET:api parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *json = responseObject;
            if (![json[@"state"] isEqualToString:@"success"]) {
                if ([json[@"state"] isEqualToString:@"error"]) {
                    self.error = [NSError cw_errorWithDomain:PRHTTPFetcherErrorDomain code:[json[@"error_code"] integerValue] message:json[@"error"]];
                }
                else {
                    self.error = [self serverError];
                }
                [[NSNotificationCenter defaultCenter] cw_postNotificationOnMainThreadName:PRHTTPFetcherDidFetchCommentsNotification sender:self userObject:nil];
                [self safelyCallback:block];
                
                return;
            }
            
            NSDictionary *resultDict = json[@"result"];
            article.comment_csrf = resultDict[@"token"];
            [[PRDatabase sharedDatabase] storeArticle:article];
            
            NSMutableArray *all = [[NSMutableArray alloc] init];
            NSMutableArray *hotComments = [[NSMutableArray alloc] init];
            NSMutableArray *comments = [[NSMutableArray alloc] init];
            
            NSArray *cmntList = resultDict[@"cmntlist"];
            NSDictionary *cmntStore = resultDict[@"cmntstore"];
            NSDictionary *cmntDict = resultDict[@"cmntdict"];
            
            NSArray *hotList = resultDict[@"hotlist"];
            if (![hotList  isEqual: @""]) {
                for (NSDictionary *hotDict in hotList) {
                    NSString *cid = hotDict[@"tid"];
                    NSDictionary *commentDict = cmntStore[cid];
                    
                    if (commentDict) {
                        PRComment *hotComment = [PRComment instanceFromDictionary:commentDict];
                        hotComment.isHot = YES;
                        [hotComments addObject:hotComment];
                    }
                }
            }
            
            if ([hotComments count] > 0) {
                [all addObject:hotComments];
            }
            
            for (NSDictionary *d in cmntList) {
                NSString *cid = d[@"tid"];
                NSDictionary *commentDict = cmntStore[cid];
                if (commentDict) {
                    PRComment *comment = [PRComment instanceFromDictionary:commentDict];
                    
                    NSMutableArray *subComments = [[NSMutableArray alloc] init];
                    
                    if ([cmntDict isKindOfClass:[NSDictionary class]]) {
                        NSArray *subArray = cmntDict[cid];
                        for (int i = 1; i <= subArray.count; i++) {
                            NSDictionary *sub = subArray[i-1];
                            NSDictionary *subCommentDict = cmntStore[sub[@"tid"]];
                            if (subCommentDict) {
                                PRComment *subComment = [PRComment instanceFromDictionary:subCommentDict];
                                subComment.floorNumber = i;
                                [subComments addObject:subComment];
                            }
                        }
                        comment.subcomments = subComments;
                    }
                    comment.floorNumber = cmntList.count - [cmntList indexOfObject:d];
                    [comments addObject:comment];
                }
            }
            
            if ([comments count] > 0) {
                [all addObject:comments];
            }
            self.responseObject = all;
            [[NSNotificationCenter defaultCenter] cw_postNotificationOnMainThreadName:PRHTTPFetcherDidFetchCommentsNotification sender:self userObject:all];
            [self safelyCallback:block];
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        [[NSNotificationCenter defaultCenter] cw_postNotificationOnMainThreadName:PRHTTPFetcherDidFetchCommentsNotification sender:self userObject:nil];
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)vote:(PRComment *)comment support:(BOOL)support article:(PRArticle *)article done:(CWHTTPFetcherBlock)block
{
    NSString *token = [self cookieCSRF_TOKEN];
    if (!token) {
        self.error = [self parametersError];
        [self safelyCallback:block];
        return;
    }
    
    NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/comment/do"];
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];

    NSString *phpsession = [self cookiePHPSESSID];
    if (phpsession) {
        [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    }

    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    [parameters setObject:support ? @"support" : @"against" forKey:@"op"];
    [parameters setObject:article.comment_csrf forKey:@"_csrf"];
    [parameters setObject:comment.aid forKey:@"sid"];
    [parameters setObject:comment.cid forKey:@"tid"];

    [manager POST:api parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *json = responseObject;
        if (![json[@"state"] isEqualToString:@"success"]) {
            self.error = [self serverError];
            [self safelyCallback:block];
            return;
        }
        
        [self safelyCallback:block];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchSecurityCodeForArticle:(PRArticle *)article done:(CWHTTPFetcherBlock)block
{
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[@"_csrf"] = article.csrf_token;
    int64_t time = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    parameters[@"_"] = @(time);
    
    NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/comment/captcha?refresh=1"];
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *phpsession = [self cookiePHPSESSID];
    NSString *token = [self cookieCSRF_TOKEN];
    if (phpsession && token) {
        [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    }
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];
    
    [manager GET:api parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *json = responseObject;
        NSString *url = json[@"url"];
        if ([url length] == 0) {
            self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil];
            [self safelyCallback:block];
            
            return;
        }
        
        NSString *URLString = [NSString stringWithFormat:@"http://www.cnbeta.com%@", url];
        [self fetchSecurityCodeImageWithURLString:URLString article:article done:block];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)fetchSecurityCodeImageWithURLString:(NSString *)URLString article:(PRArticle *)article done:(CWHTTPFetcherBlock)block
{
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[@"_csrf"] = article.csrf_token;
    int64_t time = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    parameters[@"_"] = @(time);
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *token = [self cookieCSRF_TOKEN];
    NSString *phpsession = [self cookiePHPSESSID];
    if (phpsession && token) {
        [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    }
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];
    
    [manager GET:URLString parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        UIImage *image = [UIImage imageWithData:responseObject];
        self.responseObject = image;
        [self safelyCallback:block];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        DDLogError(@"%@", error);
        
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)postCommentToArticle:(PRArticle *)article content:(NSString *)content securityCode:(NSString *)code done:(CWHTTPFetcherBlock)block
{
    NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/comment/do"];
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *token = [self cookieCSRF_TOKEN];
    NSString *phpsession = [self cookiePHPSESSID];
    [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];
    
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    [parameters setObject:article.comment_csrf forKey:@"_csrf"];
    [parameters setObject:@"publish" forKey:@"op"];
    [parameters setObject:article.articleId forKey:@"sid"];
    [parameters setObject:code forKey:@"seccode"];
    [parameters setObject:content forKey:@"content"];
    [parameters setObject:@"0" forKey:@"pid"];
    
    [manager POST:api parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *json = responseObject;
        if (![json[@"state"] isEqualToString:@"success"]) {
            if ([json[@"state"] isEqualToString:@"error"]) {
                self.error = [NSError cw_errorWithDomain:PRHTTPFetcherErrorDomain code:[json[@"error_code"] integerValue] message:json[@"error"]];
            }
            else {
                self.error = [self serverError];
            }
            
            [self safelyCallback:block];
            return;
        }
        
        [self safelyCallback:block];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

- (void)replyComment:(PRComment *)comment content:(NSString *)content securityCode:(NSString *)code article:(PRArticle *)article done:(CWHTTPFetcherBlock)block
{
    NSString *api = [NSString stringWithFormat:@"http://www.cnbeta.com/comment/do"];
    AFHTTPSessionManager *manager = [self jsonSessionManager];
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString *token = [self cookieCSRF_TOKEN];
    NSString *phpsession = [self cookiePHPSESSID];
    [manager.requestSerializer setValue:[NSString stringWithFormat:@"PHPSESSID=%@; _csrf=%@", phpsession, token] forHTTPHeaderField:@"Cookie"];
    
    NSString *referer = [NSString stringWithFormat:@"http://www.cnbeta.com/articles/%@/%@.htm", [article category], [article articleId]];
    [manager.requestSerializer setValue:referer forHTTPHeaderField:@"Referer"];
    
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    [parameters setObject:@"publish" forKey:@"op"];
    [parameters setObject:article.comment_csrf forKey:@"_csrf"];
    [parameters setObject:comment.aid forKey:@"sid"];
    [parameters setObject:comment.cid forKey:@"pid"];
    [parameters setObject:code forKey:@"seccode"];
    [parameters setObject:content forKey:@"content"];
    
    [manager POST:api parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSDictionary *json = responseObject;
        if (![json[@"state"] isEqualToString:@"success"]) {
            if ([json[@"state"] isEqualToString:@"error"]) {
                self.error = [NSError cw_errorWithDomain:PRHTTPFetcherErrorDomain code:[json[@"error_code"] integerValue] message:json[@"error"]];
            }
            else {
                self.error = [self serverError];
            }
            
            [self safelyCallback:block];
            return;
        }
        
        [self safelyCallback:block];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        self.error = error;
        [self safelyCallback:block];
    }];
}

@end
