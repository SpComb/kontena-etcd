Gem::Specification.new do |s|
  s.name          = 'kontena-etcd'
  s.version       = '0.1.0'
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

  s.add_dependency 'excon', '~> 0.54.0'
end
