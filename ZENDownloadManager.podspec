
Pod::Spec.new do |s|
  s.name             = "ZENDownloadManager"
  s.version          = "0.0.1"
  s.summary          = "NSURLSession based download manager."

  s.description      = <<-DESC
                        Download large files even in background, download multiple files, resume interrupted downloads.
                       DESC

  s.homepage         = "https://github.com/Z--EN/ZENDownloadManager.git"
  s.license          = 'BSD'
  s.author           = { "Maksim Zaremba" => "zz39704@gmail.com" }
  s.source           = { :git => "https://github.com/Z--EN/ZENDownloadManager.git", :tag => s.version }

  s.ios.deployment_target = '10.0'

  s.source_files = 'ZENDownloadManager/Classes/**/*'

  s.frameworks = 'UIKit', 'Foundation'
end
