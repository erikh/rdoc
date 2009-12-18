require 'rubygems'
require 'minitest/autorun'
require 'rdoc/ri'
require 'tmpdir'
require 'fileutils'

class TestRDocRIStore < MiniTest::Unit::TestCase

  def setup
    RDoc::TopLevel.reset

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_ri_store_#{$$}"
    @s = RDoc::RI::Store.new @tmpdir

    @top_level = RDoc::TopLevel.new 'file.rb'
    @klass = @top_level.add_class RDoc::NormalClass, 'Object'
    @klass.comment = 'original'
    @cmeth = RDoc::AnyMethod.new nil, 'cmethod'
    @cmeth.singleton = true
    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth_bang = RDoc::AnyMethod.new nil, 'method!'

    @klass.add_method @cmeth
    @klass.add_method @meth
    @klass.add_method @meth_bang

    @nest_klass = @klass.add_class RDoc::NormalClass, 'SubClass'
    @nest_meth = RDoc::AnyMethod.new nil, 'method'
    @nest_incl = RDoc::Include.new 'Incl', ''

    @nest_klass.add_method @nest_meth
    @nest_klass.add_include @nest_incl

    @RMP = RDoc::Markup::Parser
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def assert_cache imethods, cmethods, modules, ancestors = {}
    expected = {
      :class_methods    => cmethods,
      :instance_methods => imethods,
      :modules          => modules,
      :ancestors        => ancestors
    }

    assert_equal expected, @s.cache
  end

  def assert_directory path
    assert File.directory?(path), "#{path} is not a directory"
  end

  def assert_file path
    assert File.file?(path), "#{path} is not a file"
  end

  def test_class_file
    assert_equal File.join(@tmpdir, 'Object', 'cdesc-Object.ri'),
                 @s.class_file('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri'),
                 @s.class_file('Object::SubClass')
  end

  def test_class_methods
    @s.cache[:class_methods]['Object'] = 'method'

    expected = { 'Object' => 'method' }

    assert_equal expected, @s.class_methods
  end

  def test_class_path
    assert_equal File.join(@tmpdir, 'Object'), @s.class_path('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass'),
                 @s.class_path('Object::SubClass')
  end

  def test_instance_methods
    @s.cache[:instance_methods]['Object'] = 'method'

    expected = { 'Object' => 'method' }

    assert_equal expected, @s.instance_methods
  end

  def test_load_cache
    cache = {
      :methods => %w[Object#method],
      :modules => %w[Object],
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.load_cache

    assert_equal cache, @s.cache
  end

  def test_load_cache_no_cache
    cache = {
      :class_methods    => {},
      :instance_methods => {},
      :modules          => [],
      :ancestors        => {},
    }

    @s.load_cache

    assert_equal cache, @s.cache
  end

  def test_load_class
    @s.save_class @klass

    assert_equal @klass, @s.load_class('Object')
  end

  def test_load_method_bang
    @s.save_method @klass, @meth_bang

    meth = @s.load_method('Object', '#method!')
    assert_equal @meth_bang, meth
  end

  def test_method_file
    assert_equal File.join(@tmpdir, 'Object', 'method-i.ri'),
                 @s.method_file('Object', 'Object#method')

    assert_equal File.join(@tmpdir, 'Object', 'method%21-i.ri'),
                 @s.method_file('Object', 'Object#method!')

    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'method%21-i.ri'),
                 @s.method_file('Object::SubClass', 'Object::SubClass#method!')

    assert_equal File.join(@tmpdir, 'Object', 'method-c.ri'),
                 @s.method_file('Object', 'Object::method')
  end

  def test_save_cache
    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @cmeth
    @s.save_class @nest_klass

    @s.save_cache

    assert_file File.join(@tmpdir, 'cache.ri')

    expected = {
      :class_methods => { 'Object' => %w[cmethod] },
      :instance_methods => { 'Object' => %w[method] },
      :modules => %w[Object Object::SubClass],
      :ancestors => {
        'Object'           => %w[Object],
        'Object::SubClass' => %w[Incl Object],
      },
    }

    open File.join(@tmpdir, 'cache.ri'), 'rb' do |io|
      cache = Marshal.load io.read

      assert_equal expected, cache
    end
  end

  def test_save_class
    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache({}, {}, %w[Object], 'Object' => %w[Object])

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_merge
    @s.save_class @klass

    klass = RDoc::NormalClass.new 'Object'
    klass.comment = 'new class'

    s = RDoc::RI::Store.new @tmpdir
    s.save_class klass

    s = RDoc::RI::Store.new @tmpdir

    document = @RMP::Document.new(
      @RMP::Paragraph.new('original'),
      @RMP::Paragraph.new('new class'))
    assert_equal document, s.load_class('Object').comment
  end

  def test_save_class_nested
    @s.save_class @nest_klass

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri')

    assert_cache({}, {}, %w[Object::SubClass],
                 'Object::SubClass' => %w[Incl Object])
  end

  def test_save_method
    @s.save_method @klass, @meth

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')

    assert_cache({ 'Object' => %w[method] }, {}, [])

    assert_equal @meth, @s.load_method('Object', '#method')
  end

  def test_save_method_nested
    @s.save_method @nest_klass, @nest_meth

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'method-i.ri')

    assert_cache({ 'Object::SubClass' => %w[method] }, {}, [])
  end

end
