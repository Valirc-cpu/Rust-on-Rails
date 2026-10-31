# frozen_string_literal: true

module Railst
  module Terminal
    def self.color?
      $stdout.tty? && ENV["NO_COLOR"].nil?
    end

    def self.badge(text, bg: :green, fg: :black)
      return "[#{text}]" unless color?

      bg_code = case bg
      when :green then "42"
      when :red then "41"
      when :yellow then "43"
      when :blue then "44"
      when :cyan then "46"
      when :magenta then "45"
      else "40"
      end

      fg_code = case fg
      when :black then "30"
      when :white then "97"
      when :bright_white then "1;37"
      else "37"
      end

      "\e[#{fg_code};#{bg_code}m\e[1m #{text} \e[0m"
    end

    def self.bold(text)
      color? ? "\e[1m#{text}\e[0m" : text.to_s
    end

    def self.dim(text)
      color? ? "\e[90m#{text}\e[0m" : text.to_s
    end

    def self.cyan(text)
      color? ? "\e[36m#{text}\e[0m" : text.to_s
    end

    def self.bold_cyan(text)
      color? ? "\e[1;36m#{text}\e[0m" : text.to_s
    end

    def self.yellow(text)
      color? ? "\e[33m#{text}\e[0m" : text.to_s
    end

    def self.bold_yellow(text)
      color? ? "\e[1;33m#{text}\e[0m" : text.to_s
    end

    def self.red(text)
      color? ? "\e[31m#{text}\e[0m" : text.to_s
    end

    def self.bold_red(text)
      color? ? "\e[1;31m#{text}\e[0m" : text.to_s
    end

    def self.green(text)
      color? ? "\e[32m#{text}\e[0m" : text.to_s
    end

    def self.bold_green(text)
      color? ? "\e[1;32m#{text}\e[0m" : text.to_s
    end

    def self.magenta(text)
      color? ? "\e[35m#{text}\e[0m" : text.to_s
    end

    def self.bold_magenta(text)
      color? ? "\e[1;35m#{text}\e[0m" : text.to_s
    end
  end
end
