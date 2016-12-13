lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kontena/etcd'

Gem::Specification.new do |s|
  s.name          = 'kontena-etcd'
  s.version       = Kontena::Etcd::VERSION
  s.summary       = "Kontena etcd"
  s.authors       = [
    "Tero Marttila",
  ]
  s.email         = [
    "tero.marttila@kontena.io",
  ]
  s.description   = ""

  s.executables   = []
  s.require_paths = ['lib']
end
