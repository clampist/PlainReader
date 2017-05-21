//
//  PRParser.m
//  PlainReader
//
//  Created by guojiubo on 14-5-10.
//  Copyright (c) 2014年 guojiubo. All rights reserved.
//

#import "PRArticleParser.h"
#import "TFHppleElement+PRAdditions.h"

NSString *const XPathQueryArticleImages = @"//div[@class=\"content\"]//img";

@implementation PRArticleParser

+ (void)parseArticle:(PRArticle *)article hpple:(TFHpple *)hpple
{
    // 时间
    if (!article.pubTime) {
        TFHppleElement *timeElement = [[hpple searchWithXPathQuery:@"//div[@class=\"meta\"]/span"] firstObject];
        NSString *pubTime = [timeElement text];
        if ([pubTime containsString:@"年"])
            [pubTime stringByReplacingOccurrencesOfString:@"年" withString:@"-"];
        if ([pubTime containsString:@"月"])
            [pubTime stringByReplacingOccurrencesOfString:@"月" withString:@"-"];
        if ([pubTime containsString:@"日"])
            [pubTime stringByReplacingOccurrencesOfString:@"日" withString:@"-"];
        article.pubTime = pubTime;
    }
    
    // 来源
    TFHppleElement *sourceElement = [[hpple searchWithXPathQuery:@"//span[@class=\"source\"]/a/span"] firstObject];
    if (!sourceElement) {
        sourceElement = [[hpple searchWithXPathQuery:@"//span[@class=\"source\"]/a"] firstObject];
    }
    article.source = sourceElement.text;
    
    // 摘要
    TFHppleElement *summaryElement = [[hpple searchWithXPathQuery:@"//div[@class=\"article-summary\"]/p"] lastObject];
    NSString *summary = summaryElement.raw;
    article.summary = summary;
    
    // 内容
    TFHppleElement *contentElement = [[hpple searchWithXPathQuery:@"//div[@class=\"article-content\"]"] firstObject];
    NSString *content = [contentElement raw];
    if (content) {        
        // 去除内联样式
        NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@" style=\"[^\"]*\"" options:NSRegularExpressionCaseInsensitive error:nil];
        content = [reg stringByReplacingMatchesInString:content options:kNilOptions range:NSMakeRange(0, [content length]) withTemplate:@""];
        article.content = content;
    }
    
    // sn
    NSString *wholeHTML = [[NSString alloc] initWithData:hpple.data encoding:NSUTF8StringEncoding];
    if (wholeHTML) {
        NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"SN:\"([^\"]*)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [reg firstMatchInString:wholeHTML options:0 range:NSMakeRange(0, [wholeHTML length])];
        if ([match numberOfRanges] > 0) {
            NSString *sn = [wholeHTML substringWithRange:[match rangeAtIndex:1]];
            article.sn = sn;
        }
        
        reg = [NSRegularExpression regularExpressionWithPattern:@"csrf-token\" content=\"([^\"]*)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        match = [reg firstMatchInString:wholeHTML options:0  range:NSMakeRange(0, wholeHTML.length)];
        if (match.numberOfRanges > 0) {
            NSString *ArticleToken = [wholeHTML substringWithRange:[match rangeAtIndex:1]];
            article.csrf_token = ArticleToken;
        }
    }
}

@end
