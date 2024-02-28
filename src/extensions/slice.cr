struct Slice(T)
  def to_json(json : JSON::Builder)
    to_a.to_json(json)
  end
end
