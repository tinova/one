require 'sqlite3'

# Open a database
db = SQLite3::Database.new "test.db"

puts "pues la ha creado bien"
