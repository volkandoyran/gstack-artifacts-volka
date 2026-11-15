import XCTest
@testable import VitrinCore

/// Sitelerin gerçek yanıt biçimlerinden örneklenmiş (başlıkları nötrleştirilmiş) verilerle ayrıştırıcı testleri.
final class ProviderParsingTests: XCTestCase {

    // MARK: Eporner

    func testEpornerResponse() throws {
        let json = #"""
        {"count":1,"start":0,"per_page":1,"page":1,"time_ms":4,"total_count":100000,"total_pages":100000,
         "videos":[{"id":"27zf5ImSu7z","title":"Sample Clip 67","keywords":"blonde, massage, small","views":285,
           "rate":"4.50","url":"https:\/\/www.eporner.com\/video-27zf5ImSu7z\/sample\/","added":"2026-11-13 22:22:15",
           "length_sec":1291,"length_min":"21:31","embed":"https:\/\/www.eporner.com\/embed\/27zf5ImSu7z\/",
           "default_thumb":{"size":"big","width":640,"height":360,"src":"https:\/\/static-ca-cdn.eporner.com\/thumbs\/7_360.jpg"},
           "thumbs":[]}]}
        """#
        let r = try JSONDecoder().decode(EpornerProvider.Response.self, from: Data(json.utf8))
        let v = try XCTUnwrap(EpornerProvider.videos(from: r, kind: .real).first)
        XCTAssertEqual(v.id, "eporner:27zf5ImSu7z")
        XCTAssertEqual(v.durationSec, 1291)
        XCTAssertEqual(v.views, 285)
        XCTAssertEqual(v.rating, 90, accuracy: 0.01)
        XCTAssertEqual(v.tags, ["blonde", "massage", "small"])
        XCTAssertEqual(v.embedURL?.absoluteString, "https://www.eporner.com/embed/27zf5ImSu7z/")
        XCTAssertNotNil(v.addedAt)
        XCTAssertNotNil(v.thumbnail)
    }

    // MARK: Pornhub / RedTube

    func testPornhubFlatEntries() throws {
        let json = #"""
        {"videos":[{"duration":"3:01","views":40,"video_id":"6aefe3bd89f78","rating":100,"ratings":1,
          "title":"Sample: Clip 12","url":"https://www.pornhub.com/view_video.php?viewkey=6aefe3bd89f78",
          "default_thumb":"https://pix-fl.phncdn.com/x/plain/rs:fit:240:180/vts:126?hdnea=st=1~exp=2",
          "thumb":"https://pix-fl.phncdn.com/x.jpg","publish_date":"2026-11-15 14:00:05",
          "thumbs":[{"size":"240x180","width":"240","height":"180","src":"https://pix/x.jpg"}],
          "tags":[{"tag_name":"pov"},{"tag_name":"massage"}],"pornstars":[],"categories":[{"category":"amateur"}],
          "segment":"straight"}]}
        """#
        let list = try WebmasterAPI.videos(from: Data(json.utf8), provider: "pornhub", kind: .real) {
            URL(string: "https://www.pornhub.com/embed/\($0)")
        }
        let v = try XCTUnwrap(list.first)
        XCTAssertEqual(v.remoteID, "6aefe3bd89f78")
        XCTAssertEqual(v.durationSec, 181)
        XCTAssertEqual(v.rating, 100)
        XCTAssertEqual(v.tags, ["pov", "massage"])
        XCTAssertEqual(v.embedURL?.absoluteString, "https://www.pornhub.com/embed/6aefe3bd89f78")
    }

    func testRedTubeWrappedEntries() throws {
        let json = #"""
        {"videos":[{"video":{"duration":"0:21","views":7,"video_id":"309411291","rating":0,"ratings":0,
          "title":"Sample Bathroom Clip","url":"https://www.redtube.com/309411291",
          "embed_url":"https://embed.redtube.com/?id=309411291",
          "default_thumb":"https://ei-ph.rdtcdn.com/videos/202504/24/467695525/original/(m=e0YH8f)(mh=1dv5)9.jpg",
          "thumb":"https://ei-ph.rdtcdn.com/x.jpg","publish_date":"2026-11-15 01:54:11",
          "thumbs":[{"size":"medium","width":180,"height":135,"src":"https://ei/x.jpg"}],
          "tags":[{"tag_name":"HD"},{"tag_name":"amateur"}]}}],"count":1}
        """#
        let list = try WebmasterAPI.videos(from: Data(json.utf8), provider: "redtube", kind: .real) { _ in nil }
        let v = try XCTUnwrap(list.first)
        XCTAssertEqual(v.id, "redtube:309411291")
        XCTAssertEqual(v.durationSec, 21)
        XCTAssertEqual(v.embedURL?.absoluteString, "https://embed.redtube.com/?id=309411291")
        XCTAssertNotNil(v.thumbnail, "parantezli küçük resim adresleri de çözülmeli")
    }

    // MARK: XVideos / XNXX

    func testXVideosSearchBlock() throws {
        let html = #"""
        <div class="mozaique"><div id="video_ufimdcde2e5" data-id="83000781" data-eid="ufimdcde2e5" data-is-channel="1" class="frame-block thumb-block  "><div class="thumb-inside"><div class="thumb"><a href="/video.ufimdcde2e5/sample_massage_session"><img src="https://assets-cdn77.xvideos-cdn.com/img/lightbox/lightbox-blank.gif" data-src="https://thumb-cdn77.xvideos-cdn.com/16796c5d/0/xv_29_t.jpg" data-idcdn="21" data-videoid="83000781" id="pic_83000781"><span class="top-right-tags has-cc"><span class="video-hd-mark">1080p</span></span></a></div></div><div class="thumb-under"><p class="title"><a href="/video.ufimdcde2e5/sample_massage_session" title="Sample &amp; massage session">Sample &amp; massage session <span class="duration">12 min</span></a></p><p class="metadata"><span class="bg"><span class="duration">12 min</span><span><a href="/channel"><span class="name">solomon</span></a><span><span class="sprfluous"> - </span> 7M <span class="sprfluous">Views</span></span><span class="sprfluous"> - </span></span></span></p></div><script>xv.thumbs.prepareVideo('ufimdcde2e5');</script></div>
        <div id="video_abc123" data-id="555" data-eid="abc123" class="frame-block thumb-block"><div class="thumb"><a href="https://www.xvideos.com/video.abc123/second_one"><img src="https://thumb.example/2.jpg"></a></div><p class="title"><a href="https://www.xvideos.com/video.abc123/second_one" title="Second one">Second one <span class="duration">1 h 5 min</span></a></p><p class="metadata"><span class="duration">1 h 5 min</span> 18.5k <span class="sprfluous">Views</span></p></div>
        </div>
        """#
        let list = XVideosProvider.parseSearch(html: html, site: .xvideos, kind: .real)
        XCTAssertEqual(list.count, 2)
        let a = list[0]
        XCTAssertEqual(a.id, "xvideos:83000781")
        XCTAssertEqual(a.title, "Sample & massage session")
        XCTAssertEqual(a.durationSec, 720)
        XCTAssertEqual(a.views, 7_000_000)
        XCTAssertEqual(a.maxHeight, 1080)
        XCTAssertEqual(a.thumbnail?.absoluteString, "https://thumb-cdn77.xvideos-cdn.com/16796c5d/0/xv_29_t.jpg")
        XCTAssertEqual(a.pageURL?.absoluteString, "https://www.xvideos.com/video.ufimdcde2e5/sample_massage_session")
        XCTAssertEqual(a.embedURL?.absoluteString, "https://www.xvideos.com/embedframe/ufimdcde2e5")
        XCTAssertEqual(list[1].durationSec, 3900)
        XCTAssertEqual(list[1].views, 18_500)
        XCTAssertEqual(list[1].thumbnail?.absoluteString, "https://thumb.example/2.jpg")
    }

    func testXNXXSearchBlock() throws {
        let html = #"""
        <div id="video_1fdwvt5f" data-id="86309561" data-eid="1fdwvt5f" class="thumb-block with-uploader"><div class="thumb-inside"><div class="thumb"><a href="https://www.xnxx.com/video-1fdwvt5f/sample_title"><img src="https://thumb-cdn77.xnxx-cdn.com/fe8c/0/xn_14_t.jpg" data-videoid="86309561" id="pic_86309561"></a></div></div><div class="uploader"><a href="https://www.xnxx.com/porn-maker/x"><span class="name">Studio 24h</span></a></div><div class="thumb-under"><p><a href="https://www.xnxx.com/video-1fdwvt5f/sample_title" title="Sample Title's Surprise">Sample Title's Surprise</a></p><p class="metadata"><span class="right"> 876.1k <span class="icon-f icf-eye"></span><span class="superfluous">100%</span></span> 6min <span class="video-hd"><span class="superfluous"> - </span> 720p </span></p></div></div>
        """#
        let v = try XCTUnwrap(XVideosProvider.parseSearch(html: html, site: .xnxx, kind: .real).first)
        XCTAssertEqual(v.id, "xnxx:86309561")
        XCTAssertEqual(v.title, "Sample Title's Surprise")
        XCTAssertEqual(v.durationSec, 360)
        XCTAssertEqual(v.views, 876_100)
        XCTAssertEqual(v.rating, 100)
        XCTAssertEqual(v.maxHeight, 720)
        XCTAssertEqual(v.pageURL?.host, "www.xnxx.com")
    }

    func testXVideosStreamExtraction() {
        let html = """
        <script>html5player.setVideoTitle('x');
        html5player.setVideoUrlLow('https://mp4-cdn77.xvideos-cdn.com/a/0/video_240p.mp4?secure=LR==,1794793458');
        html5player.setVideoUrlHigh('https://mp4-cdn77.xvideos-cdn.com/a/0/video_360p.mp4?secure=So==,1794793458');
        html5player.setVideoHLS('https://hls-cdn77.xvideos-cdn.com/QDp2==,1794793458/a/0/hls.m3u8');</script>
        """
        let s = XVideosProvider.parseStreams(html: html)
        XCTAssertEqual(s.hls?.absoluteString, "https://hls-cdn77.xvideos-cdn.com/QDp2==,1794793458/a/0/hls.m3u8")
        XCTAssertEqual(s.high?.lastPathComponent, "video_360p.mp4")
        XCTAssertEqual(s.low?.lastPathComponent, "video_240p.mp4")
        XCTAssertEqual(XVideosProvider.parseStreams(html: "<html></html>"), .init())
    }

    func testSearchURLs() {
        let xv = XVideosProvider.Site.xvideos, xn = XVideosProvider.Site.xnxx
        XCTAssertEqual(xv.searchURL("blonde massage", 1, .newest)?.absoluteString,
                       "https://www.xvideos.com/?k=blonde%20massage&p=0&sort=uploaddate")
        XCTAssertEqual(xv.searchURL("", 1, .relevance)?.absoluteString, "https://www.xvideos.com/")
        XCTAssertEqual(xn.searchURL("blonde massage", 1, .relevance)?.absoluteString, "https://www.xnxx.com/search/blonde+massage")
        XCTAssertEqual(xn.searchURL("blonde", 3, .relevance)?.absoluteString, "https://www.xnxx.com/search/blonde/2")
        XCTAssertNil(xn.searchURL("", 1, .relevance))
    }

    // MARK: WordPress (doeda vb.)

    func testWordPressPosts() throws {
        let json = #"""
        [{"id":65392,"date":"2026-11-14T13:10:22","date_gmt":"2026-11-14T10:10:22","slug":"ornek",
          "link":"http:\/\/www.doeda.com\/ornek-video\/","title":{"rendered":"Masaj Salonunda &#8211; Örnek Başlık"},
          "featured_media":65411,"categories":[8,30],"class_list":["post-65392","post","type-post","category-18-yas-x","category-amator","category-masaj-1","tag-hd"],
          "views":"131",
          "_embedded":{"author":[{"id":2}],
            "wp:featuredmedia":[{"id":65411,"source_url":"http:\/\/www.doeda.com\/wp-content\/uploads\/2026\/11\/ornek.jpeg",
              "media_details":{"width":900,"height":600,"sizes":{"medium":{"source_url":"http:\/\/www.doeda.com\/wp-content\/uploads\/2026\/11\/ornek-300x200.jpeg"}}}}],
            "wp:term":[[{"taxonomy":"category","name":"Amatör","slug":"amator"}],[]]}},
         {"id":7,"date_gmt":"2026-11-02T11:40:33","link":"https:\/\/ornek.com\/b\/","title":{"rendered":"Görselsiz yazı"},
          "featured_media":0,"meta":[],"_embedded":{"wp:featuredmedia":[{"code":"rest_post_invalid_id","message":"x","data":{"status":404}}]}}]
        """#
        let list = try WordPressProvider.videos(from: Data(json.utf8), site: .doeda, kind: .real)
        XCTAssertEqual(list.count, 2)
        let v = list[0]
        XCTAssertEqual(v.id, "wp-doeda.com:65392")
        XCTAssertEqual(v.title, "Masaj Salonunda – Örnek Başlık")
        XCTAssertEqual(v.views, 131)
        XCTAssertEqual(v.thumbnail?.absoluteString, "http://www.doeda.com/wp-content/uploads/2026/11/ornek.jpeg")
        XCTAssertEqual(v.pageURL?.absoluteString, "http://www.doeda.com/ornek-video/")
        XCTAssertEqual(v.tags, ["18 yas", "amator", "masaj", "hd"])
        XCTAssertEqual(v.durationSec, 0)
        XCTAssertNotNil(v.addedAt)
        XCTAssertNil(list[1].thumbnail)
        XCTAssertEqual(list[1].views, 0)
    }

    func testWordPressSearchURL() {
        let p = WordPressProvider(site: .doeda)
        let url = p.searchURL(SearchQuery(terms: ["masaj", "sarışın"], kind: .real, sort: .newest, page: 2))
        let s = url?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("http://www.doeda.com/wp-json/wp/v2/posts?"), s)
        XCTAssertTrue(s.contains("page=2") && s.contains("orderby=date") && s.contains("search=masaj%20sar"), s)
        // Hentai aramasında terimin başına "hentai" eklenir
        let h = p.searchURL(SearchQuery(terms: ["elf"], kind: .hentai, sort: .relevance, page: 1))?.absoluteString ?? ""
        XCTAssertTrue(h.contains("search=hentai%20elf") && h.contains("orderby=relevance"), h)
    }

    func testFindPlayerVariants() throws {
        let page = URL(string: "http://www.doeda.com/ornek-video/")!
        let jet = #"""
        <div id="video"><iframe src="https://ads.exoclick.com/banner.html"></iframe>
        <div class="screen"><iframe src="https://www.canlitvnews3.xyz/player/play.php?vid=dcfe69de042418c1a17eecba692b4ccf" width="100%" allowfullscreen></iframe></div></div>
        """#
        guard case .jetPlayer(let base, let vid, let frame)? = WordPressProvider.findPlayer(html: jet, pageURL: page) else {
            return XCTFail("jet player bekleniyordu")
        }
        XCTAssertEqual(base.absoluteString, "https://www.canlitvnews3.xyz/player/")
        XCTAssertEqual(vid, "dcfe69de042418c1a17eecba692b4ccf")
        XCTAssertEqual(frame.host, "www.canlitvnews3.xyz")

        let generic = #"<p>x</p><iframe data-src="//player.example.net/e/abc123" allowfullscreen></iframe>"#
        XCTAssertEqual(WordPressProvider.findPlayer(html: generic, pageURL: page),
                       .iframe(URL(string: "https://player.example.net/e/abc123")!))

        let direct = #"<video controls><source src="https://cdn.example.net/v/master.m3u8?t=1&amp;k=2" type="application/x-mpegURL"></video>"#
        XCTAssertEqual(WordPressProvider.findPlayer(html: direct, pageURL: page),
                       .direct(URL(string: "https://cdn.example.net/v/master.m3u8?t=1&k=2")!))

        XCTAssertNil(WordPressProvider.findPlayer(html: #"<iframe src="https://www.googletagmanager.com/ns.html"></iframe>"#, pageURL: page))
    }

    func testJetSources() {
        let ok = #"{"status":"true","source":[{"file":"https:\/\/cdn.example\/v\/480.mp4","label":"480p","type":"mp4"},{"file":"https:\/\/cdn.example\/v\/720.mp4","label":"720p HD","type":"mp4"}],"image":"x","alternative":"b"}"#
        let s = WordPressProvider.parseJetSources(Data(ok.utf8))
        XCTAssertEqual(s.variants.map(\.height), [720, 480])
        XCTAssertFalse(s.failed)

        let frame = #"{"source":"x","iframe":"\/\/host.example\/e\/1"}"#
        XCTAssertEqual(WordPressProvider.parseJetSources(Data(frame.utf8)).iframe?.absoluteString, "https://host.example/e/1")

        let fail = WordPressProvider.parseJetSources(Data(#"{"status":"false","alternative":"fembed"}"#.utf8))
        XCTAssertTrue(fail.failed)
        XCTAssertEqual(fail.alternative, "fembed")
        XCTAssertTrue(fail.variants.isEmpty)

        XCTAssertTrue(WordPressProvider.parseJetSources(Data("<html>".utf8)).failed)
    }

    func testCustomSite() {
        let s = WordPressSite.custom(name: "", address: " ornek-site.com/ ", language: .tr, hentaiOnly: false)
        XCTAssertEqual(s?.baseURL, "https://ornek-site.com")
        XCTAssertEqual(s?.id, "wp-ornek-site.com")
        XCTAssertEqual(s?.name, "ornek-site.com")
        XCTAssertNil(WordPressSite.custom(name: "x", address: "bozuk", language: .tr, hentaiOnly: false))
        XCTAssertEqual(WordPressSite.custom(name: "A", address: "http://a.b.com", language: .en, hentaiOnly: true)?.baseURL, "http://a.b.com")
    }

    // MARK: HLS

    func testHLSMasterParsing() {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=423936,RESOLUTION=444x250,NAME="250p"
        hls-250p-ab12.m3u8
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=4500000,RESOLUTION=1920x1080,NAME="1080p"
        hls-1080p-cd34.m3u8?x=1
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2100000,RESOLUTION=1280x720,NAME="720p"

        https://other.example/720.m3u8
        """
        let base = URL(string: "https://hls.example/tok==,123/a/0/hls.m3u8")!
        let v = HLS.parse(master: master, baseURL: base)
        XCTAssertEqual(v.map(\.height), [0, 1080, 720, 250])
        XCTAssertEqual(v[0].url, base)
        XCTAssertEqual(v[0].label, "Otomatik")
        XCTAssertEqual(v[1].url.absoluteString, "https://hls.example/tok==,123/a/0/hls-1080p-cd34.m3u8?x=1")
        XCTAssertEqual(v[2].url.absoluteString, "https://other.example/720.m3u8")
        // Ana liste değilse sadece "Otomatik"
        XCTAssertEqual(HLS.parse(master: "#EXTM3U\n#EXTINF:4,\nseg0.ts", baseURL: base).map(\.height), [0])
    }

    // MARK: Biçim yardımcıları

    func testFormatHelpers() {
        XCTAssertEqual(Fmt.seconds(fromLoose: "12 min"), 720)
        XCTAssertEqual(Fmt.seconds(fromLoose: "1 h 5 min"), 3900)
        XCTAssertEqual(Fmt.seconds(fromLoose: "1h 12min"), 4320)
        XCTAssertEqual(Fmt.seconds(fromLoose: "45 sec"), 45)
        XCTAssertEqual(Fmt.seconds(fromClock: "1:02:03"), 3723)
        XCTAssertEqual(Fmt.count(fromCompact: "7M"), 7_000_000)
        XCTAssertEqual(Fmt.count(fromCompact: "876.1k"), 876_100)
        XCTAssertEqual(Fmt.count(fromCompact: "18,093"), 18_093)
        XCTAssertEqual("Tom &amp; Jerry&#8217;s &#x41;".htmlDecoded, "Tom & Jerry’s A")
        XCTAssertEqual("Sarışın ÇİFT Öğle".asciiFolded, "sarisin cift ogle")
        XCTAssertEqual("<b>a</b>&nbsp;b".strippingTags.wordTokens, ["a", "b"])
    }
}
