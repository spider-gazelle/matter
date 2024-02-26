class Socket < IO
  def sgetsockopt(optname, optval, level = LibC::SOL_SOCKET)
    system_getsockopt(fd, optname, optval, level)
  end
end
