# Copyright (C) 2013-2015 all contributors <dtas-all@nongnu.org>
# License: GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.txt)
require './test/player_integration'
require 'tmpdir'
class TestFormatChange < Testcase
  include PlayerIntegration

  def test_format_change
    s = client_socket
    default_pid = default_sink_pid(s)
    Dir.mktmpdir do |dir|
      d = "#{dir}/dump.$CHANNELS.$RATE"
      f44100 = File.open("#{dir}/dump.2.44100", IO::RDWR|IO::CREAT)
      f88200 = File.open("#{dir}/dump.2.88200", IO::RDWR|IO::CREAT)
      s.req_ok("sink ed dump active=true command='cat > #{d}'")
      noise, len = tmp_noise
      s.req_ok(%W(enq #{noise.path}))
      wait_files_not_empty(default_pid, f44100)

      s.req_ok("format rate=88200")

      wait_files_not_empty(f88200)

      dethrottle_decoder(s)

      Timeout.timeout(len) do
        begin
          cur = YAML.load(s.req("current"))
        end while cur["sinks"] && sleep(0.01)
      end

      c = "sox -R -ts32 -c2 -r88200 #{dir}/dump.2.88200 " \
          "-ts32 -c2 -r44100 #{dir}/part2"
      assert(system(c), c)

      c = "sox -R -ts32 -c2 -r44100 #{dir}/dump.2.44100 " \
          "-ts32 -c2 -r44100 #{dir}/part2 #{dir}/res.sox"
      assert(system(c), c)

      assert_equal `soxi -s #{dir}/res.sox`, `soxi -s #{noise.path}`
      File.unlink(*Dir["#{dir}/*"].to_a)
    end
  end
end
