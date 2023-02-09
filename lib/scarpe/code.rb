class Scarpe
  class Code < Scarpe::TextWidget
    def initialize(text)
      @text = text
    end

    def element
      HTML.render do |h|
        h.code { @text }
      end
    end
  end
end