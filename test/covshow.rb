# Copyright (C) 2013-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
#
# this works with the __covmerge method in test/helper.rb
# run this file after all tests are run

# load the merged dump data
res = Marshal.load(IO.binread("coverage.dump"))

# Dirty little text formatter.  I tried simplecov but the default
# HTML+JS is unusable without a GUI (I hate GUIs :P) and it would've
# taken me longer to search the Internets to find a plain-text
# formatter I like...
res.keys.sort.each do |filename|
  cov = res[filename]
  puts "==> #{filename} <=="
  File.readlines(filename).each_with_index do |line, i|
    n = cov[i]
    if n == 0 # BAD
      print("  *** 0 #{line}")
    elsif n
      printf("% 7u %s", n, line)
    elsif line =~ /\S/ # probably a line with just "end" in it
      print("        #{line}")
    else # blank line
      print "\n" # don't output trailing whitespace on blank lines
    end
  end
end
