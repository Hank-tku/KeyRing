# 向 Runner.xcodeproj 添加 CredentialProvider（AutoFill 扩展）target。
# 幂等：重复运行会先移除已存在的同名 target。
require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
TARGET_NAME = 'CredentialProvider'
BUNDLE_ID_SUFFIX = 'CredentialProvider'
ENTITLEMENTS = 'CredentialProvider/CredentialProvider.entitlements'

project = Xcodeproj::Project.open(PROJECT)

# 幂等清理
project.targets.select { |t| t.name == TARGET_NAME }.each do |t|
  t.remove_from_project
end

group = project.main_group['CredentialProvider'] || project.main_group.new_group('CredentialProvider', 'CredentialProvider')
# 清理旧引用后重新添加，保证幂等
group.files.each { |f| f.remove_from_project }

vc_ref = group.new_file('ViewController.swift')
plist_ref = group.new_file('Info.plist')
ent_ref = group.new_file('CredentialProvider.entitlements')

target = project.new_target(
  :app_extension, TARGET_NAME, :ios, '13.0'
)

target.add_file_references([vc_ref])

# Build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.example.keyRing.#{BUNDLE_ID_SUFFIX}"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ENTITLEMENTS
  config.build_settings['INFOPLIST_FILE'] = 'CredentialProvider/Info.plist'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
end

# 主 app：依赖 + Embed
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

runner.add_dependency(target)

embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
              runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/PlugIns'
embed_phase.dst_subfolder_spec = '13' # plug-ins

# 避免重复添加
products_group = project.main_group['Products']
existing = embed_phase.files.map(&:file_ref).compact.any? { |f| f.path == "#{TARGET_NAME}.appex" }
unless existing
  product_ref = products_group.children.find { |p| p.respond_to?(:path) && p.path == "#{TARGET_NAME}.appex" } ||
                products_group.new_product_ref_for_target(TARGET_NAME, :app_extension)
  embed_phase.add_file_reference(product_ref)
end

# Runner 使用 App Group entitlements
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.save
puts "OK: #{TARGET_NAME} target added"
