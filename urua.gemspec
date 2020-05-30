Gem::Specification.new do |s|
  s.name             = "urua"
  s.version          = "0.99.4447"
  s.platform         = Gem::Platform::RUBY
  s.license          = "GPL-3.0"
  s.summary          = "OPC UA Server for Universal Robots"

  s.description      = "OPC UA Server for Universal Robots. See https://github.com/fpauker/urua"

  s.files            = Dir['{lib/**/*.rb,lib/**/*.conf,tools/**/*.rb,server/**/*}'] + %w(LICENSE Rakefile README.md AUTHORS)
  s.require_path     = 'lib'
  s.extra_rdoc_files = ['README.md']
  s.bindir           = 'tools'
  s.executables      = ['urua']

  s.required_ruby_version = '>=2.4.0'

  s.authors          = ['Florian Pauker','Juergen eTM Mangler']

  s.email            = 'florian.pauker@gmail.com'
  s.homepage         = 'https://github.com/fpauker/urua'

  s.add_runtime_dependency 'opcua', '~>0.18'
  s.add_runtime_dependency 'ur-sock', '>=0.4444'
  s.add_runtime_dependency 'daemonite', '~>0.5'
end
