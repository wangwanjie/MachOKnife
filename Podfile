platform :osx, '13.0'

project 'MachOKnife.xcodeproj'

install! 'cocoapods', :warn_for_unused_master_specs_repo => false

inhibit_all_warnings!

target 'MachOKnife' do
  use_frameworks! :linkage => :static

  pod 'ViewScopeServer',
      :podspec => 'https://raw.githubusercontent.com/wangwanjie/ViewScope/v1.2.1/ViewScopeServer/ViewScopeServer.podspec',
      :configurations => ['Debug']

  target 'MachOKnifeTests' do
    inherit! :search_paths
  end

  target 'MachOKnifeUITests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
