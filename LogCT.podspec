Pod::Spec.new do |s|
    s.name             = 'LogCT'
    s.version          = '0.0.1'
    s.summary          = 'LogCT is a lightweight log collection toolkit.'

    s.homepage         = 'https://github.com/pre-dem/logct-objc'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'longbai' => 'baishunlong@qiniu.com'}
    s.source           = {:git => 'https://github.com/pre-dem/logct-objc.git', :tag => "v#{s.version}"}

    s.ios.deployment_target = '8.0'
    s.osx.deployment_target = '10.9'

    s.source_files = "LogCT/*", "Clogan/*.{h,c}"
    s.public_header_files = "LogCT/*.h"

    s.subspec 'mbedtls' do |mbedtls|
        mbedtls.source_files = "mbedtls/**/*.{h,c}"
        mbedtls.header_dir = 'mbedtls'
        mbedtls.private_header_files = "mbedtls/**/*.h"
        mbedtls.pod_target_xcconfig = { "HEADER_SEARCH_PATHS" => "${PODS_ROOT}/**"}
    end
end
