require 'pathname'
require 'markdown_helper/version'

require_relative '../test/test_helper'

# Helper class for working with GitHub markdown.
#  Supports file inclusion.
#
# @author Burdette Lamar
class MarkdownHelper

  IMAGE_REGEXP = /!\[([^\[]+)\]\(([^)]+)\)/
  INCLUDE_REGEXP = /^@\[([^\[]+)\]\(([^)]+)\)$/

  attr_accessor :pristine

  def initialize(options = {})
    default_options = {
        :pristine => false,
    }
    merged_options = default_options.merge(options)
    merged_options.each_pair do |method, value|
      unless self.respond_to?(method)
        raise ArgumentError.new("Unknown option: #{method}")
      end
      setter_method = "#{method}="
      send(setter_method, value)
      merged_options.delete(method)
    end
  end

  # Merges external files into markdown text.
  # @param template_file_path [String] the path to the input template markdown file, usually containing include pragmas.
  # @param markdown_file_path [String] the path to the output merged markdown file.
  # @return [String] the resulting markdown text.
  #
  # @example pragma to include text as a highlighted code block.
  #   @[ruby](foo.rb)
  #
  # @example pragma to include text as a plain code block.
  #   @[:code_block](foo.xyz)
  #
  # @example pragma to include text markdown, to be rendered as markdown.
  #   @[:markdown](foo.md)
  def include(template_file_path, markdown_file_path)
    send(:generate_file, template_file_path, markdown_file_path, __method__) do |input_lines, output_lines|
      send(:include_files, template_file_path, input_lines, output_lines, Inclusions.new)
    end
  end

  # Resolves relative image paths to absolute urls in markdown text.
  # @param template_file_path [String] the path to the input template markdown file, usually containing image pragmas.
  # @param markdown_file_path [String] the path to the output resolved markdown file.
  # @return [String] the resulting markdown text.
  #
  # This matters because when markdown becomes part of a Ruby gem,
  # its images will have been relocated in the documentation at RubyDoc.info, breaking the paths.
  # The resolved (absolute) urls, however, will still be valid.
  #
  # ENV['REPO_USER'] and ENV['REPO_NAME'] must give the user name and repository name of the relevant GitHub repository.
  #  must give the repo name of the relevant GitHub repository.
  #
  # @example pragma for an image:
  #   ![image_icon](images/image.png)
  #
  # The path resolves to:
  #
  #   image_path = File.join(
  #       "https://raw.githubusercontent.com/#{repo_user}/#{repo_name}/master",
  #       relative_file_path,
  #   )
  def resolve(template_file_path, markdown_file_path)
    # Method :generate_file does the first things, yields the block, does the last things.
    send(:generate_file, template_file_path, markdown_file_path, __method__) do |input_lines, output_lines|
      send(:resolve_images, template_file_path, input_lines, output_lines)
    end
  end
  alias resolve_image_urls resolve

  private

  def comment(text)
    "<!--#{text}-->\n"
  end

  def repo_user_and_name
    repo_user = ENV['REPO_USER']
    repo_name = ENV['REPO_NAME']
    unless repo_user and repo_name
      message = 'ENV values for both REPO_USER and REPO_NAME must be defined.'
      raise RuntimeError.new(message)
    end
    [repo_user, repo_name]
  end

  def generate_file(template_file_path, markdown_file_path, method)
    output_lines = []
    File.open(template_file_path, 'r') do |template_file|
      output_lines.push(comment(" >>>>>> BEGIN GENERATED FILE (#{method.to_s}): SOURCE #{template_file_path} ")) unless pristine
      input_lines = template_file.readlines
      yield input_lines, output_lines
      output_lines.push(comment(" <<<<<< END GENERATED FILE (#{method.to_s}): SOURCE #{template_file_path} ")) unless pristine
    end
    output = output_lines.join('')
    File.open(markdown_file_path, 'w') do |md_file|
      md_file.write(output)
    end
    output
  end

  def include_files(includer_file_path, input_lines, output_lines, inclusions)

    input_lines.each_with_index do |input_line, line_index|
      match_data = input_line.match(INCLUDE_REGEXP)
      unless match_data
        output_lines.push(input_line)
        next
      end
      treatment = match_data[1]
      cited_includee_file_path = match_data[2]
      treatment = case treatment
                    when ':code_block'
                      :code_block
                    when ':markdown'
                      :markdown
                    when ':verbatim'
                      message = "Treatment ':verbatim' is deprecated; please use treatment ':markdown'."
                      warn(message)
                      :markdown
                    when ':comment'
                      :comment
                    when ':pre'
                      :pre
                    else
                      treatment
                  end
      new_inclusion = Inclusion.new(
          includer_file_path,
          includer_line_number = line_index + 1,
          cited_includee_file_path
      )
      if treatment == :markdown
        inclusions.check_circularity(new_inclusion)
      end
      output_lines.push(comment(" >>>>>> BEGIN INCLUDED FILE (#{treatment}): SOURCE #{new_inclusion.absolute_includee_file_path} ")) unless pristine
      include_lines = File.readlines(new_inclusion.absolute_includee_file_path)
      unless include_lines.last.match("\n")
        message = "Warning:  Included file has no trailing newline: #{cited_includee_file_path}"
        warn(message)
      end
      case treatment
        when :markdown
          # Pass through unadorned, but honor any nested includes.
          inclusions.begin_inclusion(new_inclusion)
          include_files(new_inclusion.absolute_includee_file_path, include_lines, output_lines, inclusions)
          inclusions.end_inclusion
        when :comment
          output_lines.push(comment(include_lines.join('')))
        when :pre
          output_lines.push("<pre>\n")
          output_lines.push(include_lines.join(''))
          output_lines.push("</pre>\n")
        else
          # Use the file name as a label.
          file_name_line = format("```%s```:\n", File.basename(cited_includee_file_path))
          output_lines.push(file_name_line)
          # Put into code block.
          language = treatment == :code_block ? '' : treatment
          output_lines.push("```#{language}\n")
          output_lines.push(*include_lines)
          output_lines.push("```\n")
      end
      output_lines.push(comment(" <<<<<< END INCLUDED FILE (#{treatment}): SOURCE #{new_inclusion.absolute_includee_file_path} ")) unless pristine
    end
  end

  def resolve_images(template_file_path, input_lines, output_lines)
    input_lines.each do |input_line|
      scan_data = input_line.scan(IMAGE_REGEXP)
      if scan_data.empty?
        output_lines.push(input_line)
        next
      end
      output_lines.push(comment(" >>>>>> BEGIN RESOLVED IMAGES: INPUT-LINE '#{input_line}' ")) unless pristine
      output_line = input_line
      scan_data.each do |alt_text, path_and_attributes|
        original_image_file_path, attributes_s = path_and_attributes.split(/\s?\|\s?/, 2)

        # Attributes.
        attributes = attributes_s ? attributes_s.split(/\s+/) : []
        formatted_attributes = ['']
        attributes.each do |attribute|
          name, value = attribute.split('=', 2)
          formatted_attributes.push(format('%s="%s"', name, value))
        end
        formatted_attributes_s = formatted_attributes.join(' ')

        if original_image_file_path.start_with?('http')
          image_path = original_image_file_path
        else
          git_dir = `git rev-parse --git-dir`.chomp
          if git_dir == '.git'
            git_clone_dir_path = `pwd`.chomp
          else
            git_clone_dir_path = File.dirname(git_dir).chomp
          end
          git_clone_dir_pathname = Pathname.new(git_clone_dir_path.sub(%r|/c/|, 'C:/')).realpath
          git_clone_dir_path = git_clone_dir_pathname.to_s
          absolute_template_file_path = File.absolute_path(template_file_path)
          template_dir_path = File.dirname(absolute_template_file_path)
          absolute_file_path = File.join(
              template_dir_path,
              original_image_file_path,
          )
          absolute_file_path = Pathname.new(absolute_file_path).cleanpath.to_s
          relative_image_file_path = absolute_file_path.sub(git_clone_dir_path + '/', '')
          repo_user, repo_name = repo_user_and_name
          image_path = File.join(
              "https://raw.githubusercontent.com/#{repo_user}/#{repo_name}/master",
              relative_image_file_path,
          )
        end
        img_element = format(
            '<img src="%s" alt="%s"%s>',
            image_path,
            alt_text,
            formatted_attributes_s,
        )
        output_line = output_line.sub(IMAGE_REGEXP, img_element)
      end
      output_lines.push(output_line)
      output_lines.push(comment(" <<<<<< END RESOLVED IMAGES: INPUT-LINE '#{input_line}' ")) unless pristine
    end

  end

  class Inclusions

    def initialize
      @inclusions = []
    end

    def begin_inclusion(inclusion)
      @inclusions.push(inclusion)
    end

    def end_inclusion
      @inclusions.pop
    end

    CIRCULAR_EXCEPTION_LABEL = 'Includes are circular:'
    CIRCULAR_EXCEPTION_CLASS_NAME = 'RuntimeError'
    LEVEL_LABEL = '    Level'
    BACKTRACE_LABEL = '  Backtrace (innermost include first):'

    def check_circularity(new_inclusion)
      previous_inclusions = @inclusions.collect {|x| x.real_includee_file_path}
      previously_included = previous_inclusions.include?(new_inclusion.real_includee_file_path)
      if previously_included
        @inclusions.push(new_inclusion)
        backtrace(CIRCULAR_EXCEPTION_LABEL, @inclusions, CIRCULAR_EXCEPTION_CLASS_NAME)
      end
    end

    def backtrace(label, markdown_inclusions, exception_name)
      message_lines = ["#{label}"]
      message_lines.push(BACKTRACE_LABEL)
      markdown_inclusions.reverse.each_with_index do |inclusion, i|
        message_lines.push("#{LEVEL_LABEL} #{i}:")
        level_lines = inclusion.to_lines(indentation_level = 3)
        message_lines.push(*level_lines)
      end
      message = message_lines.join("\n")
      raise Object.const_get(exception_name).new(message)
    end

    def self.assert_level(test, level_index, level_line)
      test.assert_match(
          Regexp.new("^#{LEVEL_LABEL} #{level_index}:$"),
          level_line
      )
    end

    def self.assert_circular_exception(test, expected_values, e)
      test.assert_equal(CIRCULAR_EXCEPTION_CLASS_NAME, e.class.name)
      lines = e.message.split("\n")
      label_line = lines.shift
      test.assert_equal(CIRCULAR_EXCEPTION_LABEL, label_line)
      backtrace_line = lines.shift
      test.assert_equal(BACKTRACE_LABEL, backtrace_line)
      level_line_count = 1 + Inclusion::LINE_COUNT
      level_count = lines.size / level_line_count
      (0...level_count).each do |level_index|
        level_line = lines.shift
        inclusion_lines = lines.shift(Inclusion::LINE_COUNT)
        test.assert_equal("#{LEVEL_LABEL} #{level_index}:", level_line)
        Inclusion.assert_lines(test, expected_values[level_index], inclusion_lines)
      end
    end

  end

  class Inclusion

    LINE_COUNT = 7

    attr_accessor \
      :includer_file_path,
      :includer_line_number,
      :cited_includee_file_path,
      :absolute_includee_file_path,
      :real_includee_file_path

    def initialize(
        includer_file_path,
        includer_line_number,
        cited_includee_file_path
    )
      absolute_includee_file_path = File.join(
          File.dirname(includer_file_path),
          cited_includee_file_path,
      )
      self.includer_file_path = includer_file_path
      self.includer_line_number = includer_line_number
      self.cited_includee_file_path = cited_includee_file_path
      self.absolute_includee_file_path = absolute_includee_file_path
      self.real_includee_file_path = Pathname.new(absolute_includee_file_path).realpath.to_s
    end

    def to_lines(indentation_level)
      def indentation(level)
        '  ' * level
      end
      text = <<EOT
#{indentation(indentation_level)}Includer:
#{indentation(indentation_level+1)}File path: #{includer_file_path}
#{indentation(indentation_level+1)}Line number: #{includer_line_number}
#{indentation(indentation_level)}Includee:
#{indentation(indentation_level+1)}Cited path: #{cited_includee_file_path}
#{indentation(indentation_level+1)}Absolute path: #{absolute_includee_file_path}
#{indentation(indentation_level+1)}Real path: #{real_includee_file_path}
EOT
      text.split("\n")
    end

    def self.assert_lines(test, expected_values, actual_lines)
      # Includer label.
      actual = actual_lines.shift
      test.assert_match(/^\s*Includer:$/, actual)
      # Includer file path.
      expected_includer_file_path = expected_values[:includer][:path]
      actual = actual_lines.shift
      test.assert_match(/^\s*File path:/, actual)
      test.assert_match(Regexp.new("#{expected_includer_file_path}$"), actual)
      # Includer line number.
      expected_includer_line_number = expected_values[:includer][:line_number]
      actual = actual_lines.shift
      test.assert_match(/^\s*Line number:/, actual)
      test.assert_match(Regexp.new("#{expected_includer_line_number}$"), actual)
      # Includee label.
      actual = actual_lines.shift
      test.assert_match(/^\s*Includee:$/, actual)
      # Includee cited file path.
      expected_includee_cited_file_path = expected_values[:includee][:cited_path]
      actual = actual_lines.shift
      test.assert_match(/^\s*Cited path:/, actual)
      test.assert_match(Regexp.new("#{expected_includee_cited_file_path}$"), actual)
      # Includee relative file path.
      expected_includee_relative_file_path = expected_values[:includee][:relative_path]
      actual = actual_lines.shift
      test.assert_match(/^\s*Absolute path:/, actual)
      test.assert_match(Regexp.new("#{expected_includee_relative_file_path}$"), actual)
      # Includee real file path.
      expected_includee_real_file_path = expected_values[:includee][:real_path]
      actual = actual_lines.shift
      test.assert_match(/^\s*Real path:/, actual)
      test.assert_match(Regexp.new("#{expected_includee_real_file_path}$"), actual)
    end

  end

end

