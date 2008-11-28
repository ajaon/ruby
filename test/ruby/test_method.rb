require 'test/unit'
require_relative 'envutil'

class TestMethod < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def m0() end
  def m1(a) end
  def m2(a, b) end
  def mo1(a = nil, &b) end
  def mo2(a, b = nil) end
  def mo3(*a) end
  def mo4(a, *b, &c) end
  def mo5(a, *b, c) end
  def mo6(a, *b, c, &d) end
  def mo7(a, b = nil, *c, d, &e) end
  def ma1((a), &b) end

  class Base
    def foo() :base end
  end
  class Derived < Base
    def foo() :derived end
  end
  class T
    def initialize; end
    def normal_method; end
  end
  module M
    def func; end
    module_function :func
    def meth; end
  end

  def test_arity
    assert_equal(0, method(:m0).arity)
    assert_equal(1, method(:m1).arity)
    assert_equal(2, method(:m2).arity)
    assert_equal(-1, method(:mo1).arity)
    assert_equal(-2, method(:mo2).arity)
    assert_equal(-1, method(:mo3).arity)
    assert_equal(-2, method(:mo4).arity)
    assert_equal(-3, method(:mo5).arity)
    assert_equal(-3, method(:mo6).arity)
  end

  def test_unbind
    assert_equal(:derived, Derived.new.foo)
    um = Derived.new.method(:foo).unbind
    assert_instance_of(UnboundMethod, um)
    Derived.class_eval do
      def foo() :changed end
    end
    assert_equal(:changed, Derived.new.foo)
    assert_equal(:derived, um.bind(Derived.new).call)
    assert_raise(TypeError) do
      um.bind(Base.new)
    end
  end

  def test_callee
    assert_equal(:test_callee, __method__)
    assert_equal(:m, Class.new {def m; __method__; end}.new.m)
    assert_equal(:m, Class.new {def m; tap{return __method__}; end}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {__method__}}.new.m)
    assert_equal(:m, Class.new {define_method(:m) {tap{return __method__}}}.new.m)
    assert_nil(eval("class TestCallee; __method__; end"))
  end

  def test_body
    o = Object.new
    def o.foo; end
    assert_nothing_raised { RubyVM::InstructionSequence.disasm(o.method(:foo)) }
  end

  def test_new
    c1 = Class.new
    c1.class_eval { def foo; :foo; end }
    c2 = Class.new(c1)
    c2.class_eval { private :foo }
    o = c2.new
    o.extend(Module.new)
    assert_raise(NameError) { o.method(:bar) }
    assert_raise(NameError) { o.public_method(:foo) }
    assert_equal(:foo, o.method(:foo).call)
  end

  def test_eq
    o = Object.new
    class << o
      def foo; end
      alias bar foo
      def baz; end
    end
    assert_not_equal(o.method(:foo), nil)
    m = o.method(:foo)
    def m.foo; end
    assert_not_equal(o.method(:foo), m)
    assert_equal(o.method(:foo), o.method(:foo))
    assert_equal(o.method(:foo), o.method(:bar))
    assert_not_equal(o.method(:foo), o.method(:baz))
  end

  def test_hash
    o = Object.new
    def o.foo; end
    assert_kind_of(Integer, o.method(:foo).hash)
  end

  def test_receiver_name_owner
    o = Object.new
    def o.foo; end
    m = o.method(:foo)
    assert_equal(o, m.receiver)
    assert_equal(:foo, m.name)
    assert_equal(class << o; self; end, m.owner)
    assert_equal(:foo, m.unbind.name)
    assert_equal(class << o; self; end, m.unbind.owner)
  end

  def test_instance_method
    c = Class.new
    c.class_eval do
      def foo; :foo; end
      private :foo
    end
    o = c.new
    o.method(:foo).unbind
    assert_raise(NoMethodError) { o.foo }
    c.instance_method(:foo).bind(o)
    assert_equal(:foo, o.instance_eval { foo })
    assert_raise(NameError) { c.public_instance_method(:foo) }
    def o.bar; end
    m = o.method(:bar).unbind
    assert_raise(TypeError) { m.bind(Object.new) }
  end

  def test_define_method
    c = Class.new
    c.class_eval { def foo; :foo; end }
    o = c.new
    def o.bar; :bar; end
    assert_raise(TypeError) do
      c.class_eval { define_method(:foo, :foo) }
    end
    assert_raise(ArgumentError) do
      c.class_eval { define_method }
    end
    c2 = Class.new(c)
    c2.class_eval { define_method(:baz, o.method(:foo)) }
    assert_equal(:foo, c2.new.baz)
    assert_raise(TypeError) do
      Class.new.class_eval { define_method(:foo, o.method(:foo)) }
    end
    assert_raise(TypeError) do
      Class.new.class_eval { define_method(:bar, o.method(:bar)) }
    end

    o = Object.new
    def o.foo(c)
      c.class_eval { define_method(:foo) }
    end
    c = Class.new
    o.foo(c) { :foo }
    assert_equal(:foo, c.new.foo)

    o = Object.new
    o.instance_eval { define_singleton_method(:foo) { :foo } }
    assert_equal(:foo, o.foo)
  end

  def test_clone
    o = Object.new
    def o.foo; :foo; end
    m = o.method(:foo)
    def m.bar; :bar; end
    assert_equal(:foo, m.clone.call)
    assert_equal(:bar, m.clone.bar)
  end

  def test_call
    o = Object.new
    def o.foo; p 1; end
    def o.bar(x); x; end
    m = o.method(:foo)
    m.taint
    assert_raise(SecurityError) { m.call }
  end

  def test_inspect
    o = Object.new
    def o.foo; end
    m = o.method(:foo)
    assert_equal("#<Method: #{ o.inspect }.foo>", m.inspect)
    m = o.method(:foo)
    assert_equal("#<UnboundMethod: #{ class << o; self; end.inspect }#foo>", m.unbind.inspect)

    c = Class.new
    c.class_eval { def foo; end; }
    m = c.new.method(:foo)
    assert_equal("#<Method: #{ c.inspect }#foo>", m.inspect)
    m = c.instance_method(:foo)
    assert_equal("#<UnboundMethod: #{ c.inspect }#foo>", m.inspect)

    c2 = Class.new(c)
    c2.class_eval { private :foo }
    m2 = c2.new.method(:foo)
    assert_equal("#<Method: #{ c2.inspect }(#{ c.inspect })#foo>", m2.inspect)
  end

  def test_callee_top_level
    assert_in_out_err([], "p __callee__", %w(nil), [])
  end

  def test_caller_negative_level
    assert_raise(ArgumentError) { caller(-1) }
  end

  def test_attrset_ivar
    c = Class.new
    c.class_eval { attr_accessor :foo }
    o = c.new
    o.method(:foo=).call(42)
    assert_equal(42, o.foo)
    assert_raise(ArgumentError) { o.method(:foo=).call(1, 2, 3) }
    assert_raise(ArgumentError) { o.method(:foo).call(1) }
  end

  def test_default_accessibility
    assert T.public_instance_methods.include?(:normal_method), 'normal methods are public by default'
    assert !T.public_instance_methods.include?(:initialize), '#initialize is private'
    assert !M.public_instance_methods.include?(:func), 'module methods are private by default'
    assert M.public_instance_methods.include?(:meth), 'normal methods are public by default'
  end

  define_method(:pm0) {||}
  define_method(:pm1) {|a|}
  define_method(:pm2) {|a, b|}
  define_method(:pmo1) {|a = nil, &b|}
  define_method(:pmo2) {|a, b = nil|}
  define_method(:pmo3) {|*a|}
  define_method(:pmo4) {|a, *b, &c|}
  define_method(:pmo5) {|a, *b, c|}
  define_method(:pmo6) {|a, *b, c, &d|}
  define_method(:pmo7) {|a, b = nil, *c, d, &e|}
  define_method(:pma1) {|(a), &b|}

  def test_bound_parameters
    assert_equal([], method(:m0).parameters)
    assert_equal([[:req, :a]], method(:m1).parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:m2).parameters)
    assert_equal([[:opt, :a, nil], [:block, :b]], method(:mo1).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil]], method(:mo2).parameters)
    assert_equal([[:rest, :a]], method(:mo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:mo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:mo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:mo6).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil], [:rest, :c], [:req, :d], [:block, :e]], method(:mo7).parameters)
    assert_equal([[:req], [:block, :b]], method(:ma1).parameters)
  end

  def test_unbound_parameters
    assert_equal([], self.class.instance_method(:m0).parameters)
    assert_equal([[:req, :a]], self.class.instance_method(:m1).parameters)
    assert_equal([[:req, :a], [:req, :b]], self.class.instance_method(:m2).parameters)
    assert_equal([[:opt, :a, nil], [:block, :b]], self.class.instance_method(:mo1).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil]], self.class.instance_method(:mo2).parameters)
    assert_equal([[:rest, :a]], self.class.instance_method(:mo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], self.class.instance_method(:mo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], self.class.instance_method(:mo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], self.class.instance_method(:mo6).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil], [:rest, :c], [:req, :d], [:block, :e]], self.class.instance_method(:mo7).parameters)
    assert_equal([[:req], [:block, :b]], self.class.instance_method(:ma1).parameters)
  end

  def test_bmethod_bound_parameters
    assert_equal([], method(:pm0).parameters)
    assert_equal([[:req, :a]], method(:pm1).parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:pm2).parameters)
    assert_equal([[:opt, :a, nil], [:block, :b]], method(:pmo1).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil]], method(:pmo2).parameters)
    assert_equal([[:rest, :a]], method(:pmo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:pmo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:pmo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:pmo6).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil], [:rest, :c], [:req, :d], [:block, :e]], method(:pmo7).parameters)
    assert_equal([[:req], [:block, :b]], method(:pma1).parameters)
  end

  def test_bmethod_unbound_parameters
    assert_equal([], self.class.instance_method(:pm0).parameters)
    assert_equal([[:req, :a]], self.class.instance_method(:pm1).parameters)
    assert_equal([[:req, :a], [:req, :b]], self.class.instance_method(:pm2).parameters)
    assert_equal([[:opt, :a, nil], [:block, :b]], self.class.instance_method(:pmo1).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil]], self.class.instance_method(:pmo2).parameters)
    assert_equal([[:rest, :a]], self.class.instance_method(:pmo3).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], self.class.instance_method(:pmo4).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], self.class.instance_method(:pmo5).parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], self.class.instance_method(:pmo6).parameters)
    assert_equal([[:req, :a], [:opt, :b, nil], [:rest, :c], [:req, :d], [:block, :e]], self.class.instance_method(:pmo7).parameters)
    assert_equal([[:req], [:block, :b]], self.class.instance_method(:pma1).parameters)
  end
end
