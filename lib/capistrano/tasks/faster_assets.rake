
set :assets_dependencies, %w(app/assets app/assets/templates lib/assets vendor/assets Gemfile.lock config/routes.rb)

# clear the previous precompile task
Rake::Task["deploy:assets:precompile"].clear_actions
class PrecompileRequired < StandardError; end

namespace :deploy do
  namespace :assets do
    desc "Precompile assets"
    task :precompile do
      on roles(fetch(:assets_roles)) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            begin
              # find the most recent release
              latest_release = capture(:ls, '-xr', releases_path).split[1]

              # precompile if this is the first deploy
              raise PrecompileRequired unless latest_release

              latest_release_path = releases_path.join(latest_release)

              # precompile if the previous deploy failed to finish precompiling
              execute(:ls, shared_path.join('assets','manifest*.json')) rescue raise(PrecompileRequired)

              fetch(:assets_dependencies).each do |dep|
                # execute raises if there is a diff
                execute(:diff, '-Naur', release_path.join(dep), latest_release_path.join(dep)) rescue raise(PrecompileRequired)
              end

              puts("Skipping asset precompile, no asset diff found")

              # copy over all of the assets from the last release
              # This is useless as public/assets is symlinked !
              # execute(:cp, '-r', latest_release_path.join('public', fetch(:assets_prefix)), release_path.join('public', fetch(:assets_prefix)))

              # raise PrecompileRequired

            rescue PrecompileRequired
              # execute(:rake, "assets:precompile")


              puts "Compiling assets locally"
              %x{EXECJS_RUNTIME='Node' JRUBY_OPTS="-J-d32 -X-C" bundle exec rake assets:precompile assets:clean}

              local_manifest_path = %x{ls ./public/assets/manifest*.json}.strip

              on roles(:app) do |server|

                execute(:mv, "#{shared_path}/public/assets/", "#{shared_path}/public/oldassets/")

                info "Pushing assets to #{server.hostname}"
                info "executing : 'rsync -av ./public/assets/ #{server.user}@#{server.hostname}:#{shared_path}/public/assets/"
                %x{rsync -av ./public/assets/ #{server.user}@#{server.hostname}:#{shared_path}/public/assets/}

                info "Pushing assets manifest to #{server.hostname}"
                info "executing : 'rsync -av #{local_manifest_path} #{server.user}@#{server.hostname}:#{shared_path}/assets_manifest#{File.extname(local_manifest_path)}'"
                %x{rsync -av #{local_manifest_path} #{server.user}@#{server.hostname}:#{shared_path}/assets_manifest#{File.extname(local_manifest_path)}}

                info "Removing remote assets files"
                execute(:rm, '-rf', "#{shared_path}/public/oldassets/")
              end

              puts "Cleanning assets locally"
              %x{bundle exec rake assets:clobber}

            end
          end
        end
      end
    end
  end
end
