Pod::Spec.new do |s|

  s.name             = "FSCalendar"
  s.version          = "2.10.0"
  s.summary          = "A superiorly awesome iOS7+ calendar control, compatible with Objective-C and Swift."
  
  s.homepage         = "https://github.com/Corkscrews/FSCalendar"
  s.screenshots      = "https://cloud.githubusercontent.com/assets/5186464/10262249/4fabae40-69f2-11e5-97ab-afbacd0a3da2.jpg"
  s.license          = 'MIT'
  s.authors          = {
    "Wenchao Ding" => "f33chobits@gmail.com",
    "Pedro Paulo de Amorim" => "pp.amorim@hotmail.com"
  }
  s.source           = { :git => "https://github.com/Corkscrews/FSCalendar.git", :tag => s.version.to_s }

  s.platform     = :ios
  s.ios.deployment_target = '12.0'
  s.requires_arc = true
  s.framework    = 'UIKit', 'QuartzCore'
  s.source_files = 'FSCalendar/*.{h,m}'

end
