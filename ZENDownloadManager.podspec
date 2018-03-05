
Pod::Spec.new do |s|
  s.name             = "ZENDownloadManager"
  s.version          = "1.0"
  s.summary          = "NSURLSession based download manager."

  s.description      = <<-DESC
                        Download large files even in background, download multiple files, resume interrupted downloads.
                       DESC

  s.homepage         = "https://github.com/mzeeshanid/ZENDownloadManager"
  s.license          = 'BSD'
  s.author           = { "Maksim Zaremba" => "zz39704@gmail.com" }
  s.source           = { :git => "https://github.com/Z--EN/ZENDownloadManager.git", :tag => s.version }
  s.social_media_url = 'https://twitter.com/mzeeshanid'

  s.ios.deployment_target = '10.0'

  s.source_files = 'ZENDownloadManager/Classes/**/*'

  s.frameworks = 'UIKit', 'Foundation'
end
