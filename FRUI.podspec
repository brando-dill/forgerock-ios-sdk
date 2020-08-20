#
# Be sure to run `pod lib lint FRAuth.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'FRUI'
  s.version          = '2.1.0'
  s.summary          = 'ForgeRock Auth Proximity SDK for iOS'
  s.description      = <<-DESC
  FRUI is a SDK that allows you easily and quickly develop an application with ForgeRock Platform or ForgeRock Identity Cloud, and FRAuth SDK with pre-built UI components. FRUI SDK demonstrates most of functionalities available in FRAuth SDK which includes user authentication, registration, and identity and access management against ForgeRock solutions.
                       DESC
  s.homepage         = 'https://www.forgerock.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'ForgeRock'

  s.source           = {
      :git => 'https://github.com/ForgeRock/forgerock-ios-sdk.git',
      :tag => s.version.to_s
  }

  s.module_name   = 'FRUI'
  s.swift_versions = ['5.0', '5.1']

  s.ios.deployment_target = '10.0'

  base_dir = "FRUI/FRUI"
  s.source_files = base_dir + '/**/*.swift', base_dir + '/**/*.c', base_dir + '/**/*.h'
  s.resources = [base_dir + '/**/*.{xib, png, xcassets}', base_dir + '/Assets/*.{png, xcassets}']
  s.ios.dependency 'FRAuth', '~> 2.1.0'
end
