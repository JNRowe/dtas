module DTAS::SpawnFix # :nodoc:
  # workaround for older Rubies: https://bugs.ruby-lang.org/issues/8770
  def spawn(*args)
    super(*args)
  rescue Errno::EINTR
    retry
  end if RUBY_VERSION.to_f <= 2.1
end
