2017.5.21 修复失效接口，修改本周热门抓取地址。

enjoy~

* * *

[forked from guojiubo/PlainReader]
以下是原作者说明：

2017年4月28日更新：
[接口已失效，此项目停止维护]

简阅是我去年开发的一款 iOS(iPhone + iPad) 新闻类客户端，内容抓取自 cnBeta.COM。在售期间倍受好评，但由于版权问题已于今年一月从 AppStore 下架，下架至今，每天仍有几千人在使用这款 App。

不清楚简阅是什么的可以先观看 YouTube 上的30秒演示视频:

https://youtu.be/Ere_umItcAw

简阅完全基于客户端技术实现，希望大家不要太关注接口怎么来的之类的问题。

以下是简阅涉及到的几个关键技术，关键字列出来方便大家有针对性的看源代码：

* 全屏滑动(CWStackController)
* 网页抓取(TFHpple + XPath + NSRegularExpression)
* 夜间模式(UIAppearance + NSNotification)
* 离线阅读(NSURLProtocol + NSURLCache + CWObjectCache + SQLite3)
* 视频播放(HTML5 + JavaScript)

另外，开发期间恰逢 Swift 面世，所以里面也有少量 Swift 代码。

代码经过重构，现在开源给大家参考或学习，**请勿用于任何商业用途**。