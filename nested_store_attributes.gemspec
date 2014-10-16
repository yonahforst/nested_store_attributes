$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "nested_store_attributes/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "nested_store_attributes"
  s.version     = NestedStoreAttributes::VERSION
  s.authors     = ["Yonah Forst"]
  s.email       = ["yonaforst@hotmail.com"]
  s.summary     = "'Accept_nested_attributes_for' for collections stored in a serialized field or json column"
  s.description = "Access hashes stored on the model (serialzed to text or postgres json) using a similar syntax to accepts_nested_attributes_for "
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.1.6"

  s.add_development_dependency "sqlite3"
end
