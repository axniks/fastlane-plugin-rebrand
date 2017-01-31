require 'json'

module Fastlane
  module Actions
    class RebrandAction < Action
      def self.run(params)
        UI.message("The rebrand plugin is awake!")

        [:ipa_path, :dsym_path, :config_path, :localization_path, :asset_path].each do |key|
          verify_file(params[key])
        end

        config = JSON.parse(File.read(params[:config_path]))

        {
          ipa_path: brand_ipa(
            File.expand_path(params[:ipa_path]),
            config,
            File.expand_path(params[:localization_path]),
            File.expand_path(params[:asset_path]),
            params[:team_name],
            params[:signing_identity],
            params[:adhoc] ? params[:adhoc] : false,
            params[:app_version]
          ),
          dsym_path: brand_dsym(
            File.expand_path(params[:dsym_path]),
            config,
            params[:adhoc] ? params[:adhoc] : false,
            params[:app_version]
          )
        }
      end

      def self.description
        "Rebrand ipa with plist entries, icons and other assets"
      end

      def self.authors
        ["Axel Niklasson"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "Sets bundle id, version etc, sets up correct country block and urls"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :ipa_path,
                               description: "Path to IPA",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :dsym_path,
                               description: "Path to dSYM",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :config_path,
                               description: "Path to brand config",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :localization_path,
                               description: "Path to localizations",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :asset_path,
                               description: "Path to assets",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :team_name,
                               description: "iTunes Connect team name",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :signing_identity,
                               description: "Code signing identity",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :adhoc,
                               description: "Is this an adhoc build",
                                  optional: true,
                                 is_string: false,
                             default_value: false),
          FastlaneCore::ConfigItem.new(key: :app_version,
                               description: "App Store version, CFBundleShortVersionString",
                                  optional: true)
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end

      def self.verify_file(path)
        path = File.expand_path path
        raise "#{path} does not exist" unless File.exist? path
        UI.message path + ' file verified'
      end

      def self.brand_dsym(dsym_path, config, adhoc, app_version)
        Dir.mktmpdir do |tmp_dir|
          dsym_bundle_id = 'com.apple.xcode.dsym.' + config['CFBundleIdentifier'] + (adhoc ? '.adhoc' : '')
          brand_basename = config["basename"]

          UI.message 'Applying ' + brand_basename + ' dSYM branding'

          # unzip base dSYM to tmp dir
          sh 'cd .. && unzip -q ' + dsym_path + ' -d ' + tmp_dir

          plist_path = Dir.glob(File.join(tmp_dir, '*.app.dSYM/Contents/Info.plist')).first
          other_action.set_info_plist_value(
            path: plist_path,
            key: 'CFBundleIdentifier',
            value: dsym_bundle_id
          )

          set_app_version(plist_path, app_version)

          # create brand specific dSYM
          dsym_archive_path = File.expand_path(brand_basename + '.app.dSYM.zip')
          sh 'cd ' + tmp_dir + ' && zip -q -r ' + dsym_archive_path + ' *'
          dsym_archive_path
        end
      end

      def self.brand_ipa(ipa_path, config, localization_source_path, asset_source_path, team_name, signing_identity, adhoc, app_version)
        UI.message 'Applying ' + config["basename"] + ' IPA branding'

        Dir.mktmpdir do |tmp_dir|
          # unzip ipa to tmp dir
          sh 'cd .. && unzip -q ' + ipa_path + ' -d ' + tmp_dir

          bundle_id = config["CFBundleIdentifier"] + (adhoc ? ".adhoc" : "")
          brand_base = config["basename"]

          other_action.produce(
            skip_itc: adhoc,
            app_identifier: bundle_id,
            app_name: brand_base,
            language: 'English',
            app_version: '1.0',
            sku: brand_base + 'Mobile',
            team_name: team_name
          )

          # cert and profile
          other_action.match(
            app_identifier: bundle_id,
            type: adhoc ? 'adhoc' : 'appstore',
            force: adhoc
          )

          app_path = Dir.glob(File.join(tmp_dir, 'Payload/*.app')).first
          plist_path = File.join(app_path, 'Info.plist')

          # apply brand specific configuration
          apply_config(plist_path, config, adhoc, app_version)

          # copy image assets
          FileUtils.cp_r File.join(asset_source_path, '.'), app_path

          # copy localizations
          FileUtils.cp_r File.join(localization_source_path, '.'), app_path
          convert_to_binary(File.join(app_path, '*.lproj/*.strings'))

          # create brand specific IPA
          ipa_destination_path = File.expand_path(brand_base + '.ipa')
          sh 'cd ' + tmp_dir + ' && zip -q -r ' + ipa_destination_path + ' *'

          # get path to brand specific provisioning profile
          profile_folder = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
          profile_var_name = 'sigh_' + bundle_id + (adhoc ? '_adhoc' : '_appstore')
          profile_basename = ENV[profile_var_name] + '.mobileprovision'
          profile_path = File.join(profile_folder, profile_basename)

          # sign brand specific IPA with brand cert
          other_action.resign(
            ipa: ipa_destination_path,
            signing_identity: signing_identity,
            provisioning_profile: {
              bundle_id => profile_path
              }
          )
          ipa_destination_path
        end
      end

      def self.convert_to_binary(strings_path)
        Dir.glob(strings_path) do |strings_file|
          sh 'plutil -convert binary1 ' + strings_file
        end
      end

      def self.apply_config(plist_path, config, adhoc, app_version)
        sh 'plutil -convert xml1 ' + plist_path

        other_action.set_info_plist_value(
          path: plist_path,
          key: "CFBundleIdentifier",
          value: config["CFBundleIdentifier"] + (adhoc ? ".adhoc" : "")
        )

        other_action.set_info_plist_value(
          path: plist_path,
          key: "BRAND_CONFIG",
          value: config["BRAND_CONFIG"]
        )

        set_app_version(plist_path, app_version)

        sh 'plutil -convert binary1 ' + plist_path
      end

      def self.set_app_version(plist_path, app_version)
        other_action.set_info_plist_value(
          path: plist_path,
          key: "CFBundleShortVersionString",
          value: app_version
        )
      end
    end
  end
end
