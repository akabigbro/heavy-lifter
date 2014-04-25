require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/heavy_lifter_test.rb']
  t.verbose
end

desc "Run tests"
task :default => :test
