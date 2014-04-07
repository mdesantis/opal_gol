require 'opal'
require 'opal-jquery'
require 'set'

class GOL
  attr_reader :grid, :current_generation
  attr_reader :step_time

  CELL_HEIGHT = 15
  CELL_WIDTH  = 15

  MIN_STEP_TIME = 30

  def initialize
    @grid               = GOL::Grid.new
    @current_generation = 0
    @status             = :stopped
    @step_time          = 500
  end

  def start
    return if @interval

    @interval = `setInterval(function() { #{step} }, #{step_time})`
    @status   = :running
    `$(#{self}).trigger('start')`
  end

  def stop
    return unless @interval

    `clearInterval(#{@interval})`
    @interval = nil
    @status   = :stopped
    `$(#{self}).trigger('stop')`
  end

  def reset
    stop
    reset_cells
  end

  def step_time=(step_time)
    return if step_time < MIN_STEP_TIME

    status = @status
    stop if status == :running
    @step_time = step_time
    start if status == :running
  end

  # We call to_a in order to duplicate cells instances
  # we need it because something else could be in execution and could delete while we are trying to access them
  def reset_cells
    live_cells.to_a.each { |v| grid.unfill_cell v }
    @current_generation = 0
    `$(#{self}).trigger('reset')`
  end

  def step
    @rule_1_cells = live_cells.select { |v| v.neighbours.count { |v| grid.filled? v } < 2 }
    # rule 2 is a noop
    @rule_3_cells = live_cells.select { |v| v.neighbours.count { |v| grid.filled? v } > 3 }
    @rule_4_cells = dead_cells_neighbouring_with_live_cells.select { |v| v.neighbours.count { |v| grid.filled? v } == 3 }
    

    @rule_1_cells.each { |v| grid.unfill_cell v }
    # rule_2 noop
    @rule_3_cells.each { |v| grid.unfill_cell v }
    @rule_4_cells.each { |v| grid.fill_cell v }

    @current_generation += 1
    `$(#{self}).trigger('change')`
  end

  def live_cells
    grid.filled_cells
  end

  def dead_cells_neighbouring_with_live_cells
    live_cells.each_with_object(Set.new) do |cell, set|
      cell.neighbours.select { |v| grid.unfilled? v }.each { |v| set << v }
    end
  end

  def load_preset(preset)
    reset_cells
    PRESETS[preset].each { |cell| grid.fill_cell cell }
  end

  class Coordinates
    attr_reader :x, :y

    def initialize(x, y)
      @x, @y = x, y
    end

    def ==(other)
      self.class == other.class && x == other.x && y == other.y
    end

    def to_a
      [x, y]
    end

    # Cantor pairing function http://en.wikipedia.org/wiki/Cantor_pairing_function#Cantor_pairing_function
    def hash
      (x + y) * (x + y + 1) / 2 + x
    end

    def neighbours
      [n, ne, e, se, s, sw, w, nw]
    end

    def n  ; self.class.new(x,            y-CELL_HEIGHT) ; end
    def ne ; self.class.new(x+CELL_WIDTH, y-CELL_HEIGHT) ; end
    def e  ; self.class.new(x+CELL_WIDTH, y            ) ; end
    def se ; self.class.new(x+CELL_WIDTH, y+CELL_HEIGHT) ; end
    def s  ; self.class.new(x,            y+CELL_HEIGHT) ; end
    def sw ; self.class.new(x-CELL_WIDTH, y+CELL_HEIGHT) ; end
    def w  ; self.class.new(x-CELL_WIDTH, y            ) ; end
    def nw ; self.class.new(x-CELL_WIDTH, y-CELL_HEIGHT) ; end
  end

  s = Set.new
  s.add Coordinates.new(1, 2)
  s.add Coordinates.new(1, 2)
  # FIXME it should be 1, isntead it is 2
  p s.size

  # Opal 0.6 doesn't implement Set#delete
  class Set < Set
    unless method_defined? :delete
      def delete(o)
        @hash.delete(o)
        self
      end
    end
  end
   
  class Grid
    attr_reader :height, :width, :canvas, :context, :max_x, :max_y, :filled_cells
   
    def initialize
      @canvas       = `document.getElementById(#{canvas_id})`
      @width        = `$(#{canvas}).width()`
      @height       = `$(#{canvas}).height()`
      @context      = `#{canvas}.getContext('2d')`
      @max_x        = (height / CELL_HEIGHT).floor
      @max_y        = (width / CELL_WIDTH).floor
      @filled_cells = Set.new
    end
   
    def draw_canvas
      `#{canvas}.width  = #{width}`
      `#{canvas}.height = #{height}`
   
      x = 0.5
      until x >= width do
        `#{context}.moveTo(#{x}, 0)`
        `#{context}.lineTo(#{x}, #{height})`
        x += CELL_WIDTH
      end
   
      y = 0.5
      until y >= height do
        `#{context}.moveTo(0, #{y})`
        `#{context}.lineTo(#{width}, #{y})`
        y += CELL_HEIGHT
      end

      `#{context}.strokeStyle = "#eee"`
      `#{context}.stroke()`
    end
   
    def canvas_id
      'conwayCanvas'
    end

    def fill_cell(coordinates)
      `#{context}.fillStyle = "#000"`
      `#{context}.fillRect(#{coordinates.x+1}, #{coordinates.y+1}, #{CELL_WIDTH-1}, #{CELL_HEIGHT-1})`
      filled_cells.add coordinates
      p filled_cells.to_a.map(&:to_a)
      p filled_cells.size
    end
     
    def unfill_cell(coordinates)
      `#{context}.clearRect(#{coordinates.x+1}, #{coordinates.y+1}, #{CELL_WIDTH-1}, #{CELL_HEIGHT-1})`
      filled_cells.delete coordinates
      p filled_cells.to_a.map(&:to_a)
      p filled_cells.size
    end

    def filled?(coordinates)
      filled_cells.include? coordinates
    end

    def unfilled?(coordinates)
      not filled? coordinates
    end

    def get_cursor_position(event)
      if (event.page_x && event.page_y)
        x = event.page_x
        y = event.page_y
      else
        doc = Opal.Document[0]
        x = event[:clientX] + doc.scrollLeft +
              doc.documentElement.scrollLeft
        y = event[:clientY] + doc.body.scrollTop +
              doc.documentElement.scrollTop
      end

      x -= `#{canvas}.offsetLeft`
      y -= `#{canvas}.offsetTop`
     
      x = (x / CELL_WIDTH).floor
      y = (y / CELL_HEIGHT).floor
     
      [x, y]
    end

    def canvas_element
      Element.find("##{canvas_id}")
    end

    def add_event_listeners
      canvas_element.on :click do |event|
        x, y = get_cursor_position(event)
        x *= CELL_WIDTH
        y *= CELL_HEIGHT
        fill_cell Coordinates.new(x, y)
      end
     
      canvas_element.on :dblclick do |event|
        x, y = get_cursor_position(event)
        x *= CELL_WIDTH
        y *= CELL_HEIGHT
        unfill_cell Coordinates.new(x, y)
      end
    end
  end

  PRESETS = [ [ Coordinates.new(270, 135) ,
                Coordinates.new(285, 135) ,
                Coordinates.new(300, 135) ] ,
              # Gosper Glider Gun
              [ Coordinates.new(180, 195) ,
                Coordinates.new(180, 210) ,
                Coordinates.new(195, 210) ,
                Coordinates.new(195, 195) ,
                Coordinates.new(330, 210) ,
                Coordinates.new(330, 195) ,
                Coordinates.new(330, 225) ,
                Coordinates.new(345, 180) ,
                Coordinates.new(360, 165) ,
                Coordinates.new(375, 165) ,
                Coordinates.new(345, 240) ,
                Coordinates.new(360, 255) ,
                Coordinates.new(375, 255) ,
                Coordinates.new(405, 210) ,
                Coordinates.new(420, 180) ,
                Coordinates.new(435, 195) ,
                Coordinates.new(435, 210) ,
                Coordinates.new(450, 210) ,
                Coordinates.new(435, 225) ,
                Coordinates.new(420, 240) ,
                Coordinates.new(495, 195) ,
                Coordinates.new(495, 180) ,
                Coordinates.new(495, 165) ,
                Coordinates.new(510, 165) ,
                Coordinates.new(510, 180) ,
                Coordinates.new(510, 195) ,
                Coordinates.new(525, 150) ,
                Coordinates.new(525, 210) ,
                Coordinates.new(555, 150) ,
                Coordinates.new(555, 135) ,
                Coordinates.new(555, 210) ,
                Coordinates.new(555, 225) ,
                Coordinates.new(705, 180) ,
                Coordinates.new(705, 165) ,
                Coordinates.new(720, 165) ,
                Coordinates.new(720, 180) ] ,
              # Acorn
              [ Coordinates.new(390, 240) ,
                Coordinates.new(405, 240) ,
                Coordinates.new(405, 210) ,
                Coordinates.new(435, 225) ,
                Coordinates.new(450, 240) ,
                Coordinates.new(465, 240) ,
                Coordinates.new(480, 240) ] ]
end

gol = GOL.new
gol.step_time = 80
gol.grid.draw_canvas
gol.grid.add_event_listeners
%x{
$(#{gol}).on('stop', function() {
  $('#status').addClass('stop').removeClass('start').text('Stopped')
})
.on('start', function() {
  $('#status').addClass('start').removeClass('stop').text('Running')
  $('#current_generation').show().text('Generation: '+#{gol.current_generation})
})
.on('change', function() {
  $('#current_generation').text('Generation: '+#{gol.current_generation})
})
.on('reset', function() {
  $('#current_generation').text('Generation: '+#{gol.current_generation})
})
}

%w(start stop reset).each do |action|
  Element.find("##{action}").on(:click) { gol.send action }
end
Element.find('#set_step_time').on(:click) do
  gol.step_time = Element.find('#step_time').value.to_i
end
Element.find("#load_preset_1").on(:click) { gol.load_preset(0) }
Element.find("#load_preset_2").on(:click) { gol.load_preset(1) }
Element.find("#load_preset_3").on(:click) { gol.load_preset(2) }