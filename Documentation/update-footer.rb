#!/usr/bin/env ruby
# Copyright 2015-2020 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>
# frozen_string_literal: true
contact = %q{
All feedback welcome via plain-text mail to: L<mailto:dtas-all@nongnu.org>

Mailing list archives available at L<https://80x24.org/dtas-all/>
and L<https://lists.gnu.org/archive/html/dtas-all/>

No subscription is necessary to post to the mailing list.
}

copyright = %q{
Copyright %s all contributors L<mailto:dtas-all@nongnu.org>

License: GPL-3.0+ L<https://www.gnu.org/licenses/gpl-3.0.txt>
}

ENV['TZ'] = 'UTC'
now_year = Time.now.strftime("%Y")
ARGV.each do |file|
  cmd = %W(git log --follow -M1 --pretty=format:%ad --date=short
           -- #{file})
  beg_year = IO.popen(cmd, &:read).split("\n")[-1].split('-')[0]
  years = beg_year == now_year ? beg_year : "#{beg_year}-#{now_year}"

  File.open(file, "r+") do |fp|
    state = :top
    sections = [ state ]
    sec = { state => ''.dup }
    fp.each_line do |l|
      case l
      when /^(=head.+)$/
        state = $1.freeze
        sections << state
        sec[state] = ''.dup
      else
        sec[state] << l
      end
    end

    fp.truncate(0)
    fp.rewind
    sec["=head1 CONTACT"] = contact
    sec["=head1 COPYRIGHT"] = sprintf(copyright, years)
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
