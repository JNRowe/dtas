#!/usr/bin/env ruby
# Copyright 2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later <http://www.gnu.org/licenses/gpl-3.0.txt>
contact = %q{
All feedback welcome via plain-text mail to: <dtas-all@nongnu.org>\
Mailing list archives available at <http://80x24.org/dtas-all/> and
<ftp://lists.gnu.org/dtas-all/>\
No subscription is necessary to post to the mailing list.
}

copyright = %q{
Copyright %s all contributors <dtas-all@nongnu.org>.\
License: GPLv3 or later <http://www.gnu.org/licenses/gpl-3.0.txt>
}

ENV['TZ'] = 'UTC'
now_year = Time.now.strftime("%Y")
ARGV.each do |file|
  cmd = %W(git log --reverse --pretty=format:%ad --date=short -- #{file})
  beg_year = IO.popen(cmd, &:gets).split('-')[0]
  years = beg_year == now_year ? beg_year : "#{beg_year}-#{now_year}"

  File.open(file, "r+") do |fp|
    state = :top
    sections = [ state ]
    sec = { state => "" }
    fp.each_line do |l|
      case l
      when /^(#.+)$/
        state = $1.freeze
        sections << state
        sec[state] = ""
      else
        sec[state] << l
      end
    end

    fp.truncate(0)
    fp.rewind
    sec["# CONTACT"] = contact
    sec["# COPYRIGHT"] = sprintf(copyright, years)
    while section = sections.shift
      fp.puts(section) if String === section
      blob = sec[section].sub(/\A\n+/, '').sub(/\n+\z/, '')
      fp.puts("\n") if String === section
      fp.write(blob)
      fp.puts("\n")
      fp.puts("\n") if sections[0]
    end
    fp.rewind
  end
end
