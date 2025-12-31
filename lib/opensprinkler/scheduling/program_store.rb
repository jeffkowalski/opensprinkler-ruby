# frozen_string_literal: true

require 'yaml'
require_relative 'program'
require_relative '../constants'

module OpenSprinkler
  module Scheduling
    # Manages collection of programs with persistence
    class ProgramStore
      include Constants

      MAX_PROGRAMS = 40

      attr_reader :programs, :file_path

      def initialize(file_path: nil)
        @file_path = file_path
        @programs = []
      end

      # Get program by ID
      def [](id)
        @programs[id]
      end

      # Number of programs
      def count
        @programs.length
      end

      # Iterate over programs
      def each(&block)
        @programs.each(&block)
      end

      include Enumerable

      # Add a new program
      def add(program)
        return nil if @programs.length >= MAX_PROGRAMS

        program.id = @programs.length
        @programs << program
        program
      end

      # Modify an existing program
      def modify(id, program)
        return nil if id >= @programs.length

        program.id = id
        @programs[id] = program
        program
      end

      # Delete a program
      def delete(id)
        return nil if id >= @programs.length

        @programs.delete_at(id)
        # Re-index remaining programs
        @programs.each_with_index { |p, i| p.id = i }
        true
      end

      # Delete all programs
      def clear
        @programs.clear
      end

      # Move a program up (swap with previous)
      def move_up(id)
        return nil if id.zero? || id >= @programs.length

        @programs[id], @programs[id - 1] = @programs[id - 1], @programs[id]
        @programs[id].id = id
        @programs[id - 1].id = id - 1
        true
      end

      # Move a program from one position to another
      def move(from, to)
        return nil if from.negative? || from >= @programs.length
        return nil if to.negative? || to >= @programs.length
        return true if from == to

        program = @programs.delete_at(from)
        @programs.insert(to, program)
        # Re-index all programs
        @programs.each_with_index { |p, i| p.id = i }
        true
      end

      # Load from YAML file
      def load
        return unless @file_path && File.exist?(@file_path)

        data = YAML.load_file(@file_path, permitted_classes: [Symbol])
        return unless data.is_a?(Hash) && data['programs'].is_a?(Array)

        @programs = data['programs'].map.with_index do |prog_data, idx|
          Program.from_h(prog_data.merge('id' => idx))
        end
      end

      # Save to YAML file
      def save
        return unless @file_path

        data = {
          'programs' => @programs.map(&:to_h)
        }
        File.write(@file_path, data.to_yaml)
      end

      # Convert to array for API
      def to_a
        @programs.map(&:to_h)
      end

      # Get programs in API format (for /jp endpoint)
      def to_api_format(num_boards:)
        {
          'nprogs' => @programs.length,
          'nboards' => num_boards,
          'mnp' => MAX_PROGRAMS,
          'mnst' => Program::MAX_STARTTIMES,
          'pnsize' => Constants::STATION_NAME_SIZE,
          'pd' => @programs.map { |p| program_to_api(p) }
        }
      end

      private

      def program_to_api(program)
        [
          program.flag_byte,
          program.days[0],
          program.days[1],
          program.starttimes,
          program.durations,
          program.name,
          [
            program.date_range_enabled ? 1 : 0,
            program.date_range[0],
            program.date_range[1]
          ]
        ]
      end
    end
  end
end
