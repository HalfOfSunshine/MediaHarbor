platform :ios, '17.0'

install! 'cocoapods', warn_for_unused_master_specs_repo: false

use_frameworks! :linkage => :static

target 'MediaHarbor' do
  pod 'MobileVLCKit', '3.7.3'
  pod 'SDWebImage', '~> 5.21'
end

target 'MediaHarborTests' do
  inherit! :search_paths
  pod 'MobileVLCKit', '3.7.3'
  pod 'SDWebImage', '~> 5.21'
end

target 'MediaHarborUITests' do
  inherit! :search_paths
  pod 'MobileVLCKit', '3.7.3'
  pod 'SDWebImage', '~> 5.21'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
