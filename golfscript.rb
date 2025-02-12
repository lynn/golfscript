#!/usr/bin/ruby
#(c) Copyright 2008 Darren Smith. All Rights Reserved.
$lb = []
class Gtype
	def initialize_copy(other); @val = other.val.dup; end
	def go; $stack<<self; end
	def val; @val; end
	def addop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.addop(b)) : factory(@val + rhs.val); end
	def subop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.subop(b)) : factory(@val - rhs.val); end
	def uniop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.uniop(b)) : factory(@val | rhs.val); end
	def intop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.intop(b)) : factory(@val & rhs.val); end
	def difop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.difop(b)) : factory(@val ^ rhs.val); end
	def ==(rhs); Gtype === rhs && @val==rhs.val; end
	def eql?(rhs); Gtype === rhs && @val==rhs.val; end
	def hash; @val.hash; end
	def <=>(rhs); @val<=>rhs.val; end
	def notop; self.falsey ? 1 : 0; end
end

class Numeric
	def addop(rhs); rhs.is_a?(Numeric) ? self + rhs : (a,b=gscoerce(rhs); a.addop(b)); end
	def subop(rhs); rhs.is_a?(Numeric) ? self - rhs : (a,b=gscoerce(rhs); a.subop(b)); end
	def uniop(rhs); rhs.is_a?(Numeric) ? self | rhs : (a,b=gscoerce(rhs); a.uniop(b)); end
	def intop(rhs); rhs.is_a?(Numeric) ? self & rhs : (a,b=gscoerce(rhs); a.intop(b)); end
	def difop(rhs); rhs.is_a?(Numeric) ? self ^ rhs : (a,b=gscoerce(rhs); a.difop(b)); end
	def to_gs; Gstring.new(to_s); end
	def ginspect; to_gs; end
	def go; $stack<<self; end
	def notop; self == 0 ? 1 : 0; end
	def class_id; 0; end
	def falsey; self == 0; end
	def ltop(rhs); self < rhs ? 1 : 0; end
	def gtop(rhs); self > rhs ? 1 : 0; end
	def equalop(rhs); self == rhs ? 1 : 0; end
	def question(b); self**b; end
	def leftparen; self-1; end
	def rightparen; self+1; end
	def gscoerce(b)
		c = b.class_id
		[if c == 1
			Garray.new([self])
		elsif c == 2
			to_gs
		else #Gblock
			to_gs.to_s.compile
		end,b]
	end
	def base(a)
		if Garray===a
			r=0
			a.val.each{|i|
				r*=self
				r+=i
			}
			r
		else
			i=a.abs
			r=[]
			while i!=0
				r.unshift(i % self)
				i/=self
			end
			Garray.new(r)
		end
	end
end

class Garray < Gtype
	def initialize(a)
		@val = a || []
	end
	def concat(rhs)
		if rhs.class != self.class
			a,b=gscoerce(rhs)
			a.addop(b)
		else
			@val.concat(rhs.val)
			self
		end
	end
	def factory(a)
		Garray.new(a)
	end
	def to_gs
		r = []
		@val.each {|i| r.concat(i.to_gs.val) }
		Gstring.new(r)
	end
	def flatten
		Garray.new(flatten_append([]))
	end
	def flatten_append(prefix)
		@val.inject(prefix){|s,i|case i
			when Numeric then s<<i
			when Garray then i.flatten_append(s)
			when Gstring then s.concat(i.val)
			when Gblock then s.concat(i.val)
 			end
		}
	end
	def ginspect
		bs = []
		@val.each{|i| bs << 32; bs.concat(i.ginspect.val) }
		bs[0] = 91
		bs << 93
		Gstring.new(bs)
	end
	def go; $stack<<self; end
	def class_id; 1; end
	def gscoerce(b)
		c = b.class_id
		if c == 0
			b.gscoerce(self).reverse
		elsif c == 2
			[Gstring.new(self),b]
		else
			[(self*Gstring.new(' ')).to_s.compile,b]
		end
	end
	
	def leftparen
		[factory(@val[1..-1]),@val[0]]
	end
	def rightparen
		[factory(@val[0..-2]),@val[-1]]
	end
	def *(b)
		if Numeric === b
			factory(@val*b)
		else
			return b*self if self.class == Gstring && b.class == Garray
			return Garray.new(@val.map{|n|Gstring.new([n])})*b if self.class == Gstring
			return b.factory([]) if @val.size<1
			r=@val.first.dup
			r,x=r.gscoerce(b) if r.class != b.class #for size 1
			@val[1..-1].each{|i|r=r.concat(b); r=r.concat(i)}
			r
		end
	end
	def /(b, no_empty=false)
		if Numeric === b
			r=[]
			a = b < 0 ? @val.reverse : @val
			i = -b = b.abs
			r << factory(a[i,b]) while (i+=b)<a.size
			Garray.new(r)
		else
			r=[]
			i=b.factory([])
			j=0
			while j<@val.size
				if @val[j,b.val.size]==b.val
					r<<i unless no_empty && i.val.empty?
					i=b.factory([])
					j+=b.val.size
				else
					i.val<<@val[j]
					j+=1
				end
			end
			r<<i unless no_empty && i.val.empty?
			Garray.new(r)
		end
	end
	def %(b)
		if Numeric === b
			factory((0..(@val.size-1)/b.abs).inject([]){|s,i|
				s<<@val[b < 0 ? i*b - 1 : i*b]
			})
		else
			self./(b, true)
		end
	end
	def falsey; @val.empty?; end
	def question(b); @val.index(b)||-1; end
	def equalop(b); Numeric === b ? @val[b] : (@val==b.val ? 1 : 0); end
	def ltop(b); Numeric === b ? factory(@val[0...b]) : (@val<b.val ? 1 : 0); end
	def gtop(b); Numeric === b ? factory(@val[[b,-@val.size].max..-1]) : (@val>b.val ? 1 : 0); end
	def sort; factory(@val.sort); end
	def zip
		r=[]
		@val.size.times{|x|
			@val[x].val.size.times{|y|
				(r[y]||=@val[0].factory([])).val<<@val[x].val[y]
			}
		}
		Garray.new(r)
	end
	def ~
		val
	end
end

class Gstring < Garray
	def initialize(a)
		@val=case a
			when NilClass then []
			when String then a.unpack('C*')
			when Array then a
			when Garray then a.flatten.val
		end
	end
	def factory(a); Gstring.new(a); end
	def to_gs; self; end
	def ginspect; factory(to_s.inspect); end
	def to_s; @val.pack('C*'); end
	def class_id; 2; end
	def gscoerce(b)
		if b.class == Gblock
			[to_s.compile,b]
		else
			b.gscoerce(self).reverse
		end
	end
	def question(b)
		if b.class == Gstring
			(to_s.index(b.to_s)||-1)
		elsif b.class == Garray
			b.question(self)
		else
			(@val.index(b)||-1)
		end
	end
	def ~; to_s.compile.go; nil; end
end

class Gblock < Garray
	def initialize(_a,_b=nil)
		@val=Gstring.new(_b).val
		@native = eval("lambda{#{_a}}")
	end
	def go; @native.call; end
	def factory(b); Gstring.new(b).to_s.compile; end
	def class_id; 3; end
	def to_gs; Gstring.new(([123]+@val)<<125); end
	def ginspect; to_gs; end
	def gscoerce(b); b.gscoerce(self).reverse; end
	def addop(b)
		if b.class != self.class
			a,b=gscoerce(b)
			a.addop(b)
		else
			(@val+[32]+b.val).pack('C*').compile
		end
	end
	def *(b)
		if Numeric === b
			b.times{go}
		else
			gpush b.val.first
			(b.val[1..-1]||[]).each{|i|$stack<<i; go}
		end
		nil
	end
	def /(b)
		if b.class==Garray||b.class==Gstring
			b.val.each{|i|gpush i; go}
			nil
		else #unfold
			r=[]
			loop{
				$stack<<$stack.last
				go
				break if gpop.falsey;
				r<<$stack.last
				b.go
			}
			gpop
			Garray.new(r)
		end
	end
	def %(b)
		r=[]
		b.val.each{|i|
			lb=$stack.size
			$stack<<i; go
			r.concat($stack.slice!(lb..$stack.size))
		}
		r=Garray.new(r)
		b.class == Gstring ? Gstring.new(r) : r
	end
	def ~; go; nil; end
	def sort
		a=gpop
		a.factory(a.val.sort_by{|i|gpush i; go; gpop})
	end
	def select(a)
		a.factory(a.val.select{|i|gpush i;go; !gpop.falsey})
	end
	def question(b)
		b.val.find{|i|gpush i; go; !gpop.falsey}
	end
end

class NilClass
	def go; end
end

class Array
	def ^(rhs); self-rhs|rhs-self; end
	include Comparable
end

code=gets(nil)||''
$_=$stdin.isatty ? '' : $stdin.read
$stack = [Gstring.new($_)]
$var_lookup={}

def var(name,val=nil)
	eval"#{s="$_#{$var_lookup[name]||=$var_lookup.size}"}||=val"
	s
end

$nprocs=0

class String
	def compile(tokens=scan(/[a-zA-Z_][a-zA-Z0-9_]*|'(?:\\.|[^'])*'?|"(?:\\.|[^"])*"?|-?[0-9]+|#[^\n\r]*|./mn))
	 	orig=tokens.dup
		native=""
		while t=tokens.slice!(0)
			native<<case t
				when "{" then "$stack<<"+var("{#{$nprocs+=1}",compile(tokens))
				when "}" then break
				when ":" then var(tokens.slice!(0))+"=$stack.last"
				when /^["']/ then var(t,Gstring.new(eval(t)))+".go"
				when /^-?[0-9]+/ then var(t,t.to_i)+".go"
				else; var(t)+".go"
				end+"\n"
		end
		source=orig[0,orig.size-tokens.size-(t=="}"?1:0)]*""
		Gblock.new(native,source)
	end
end
def gpop
	i=$lb.size
	$lb[i] -= 1 while i>0 && $lb[i-=1] >= $stack.size
	$stack.pop
end
def gpush a
	$stack.push(*a) if a
end

class String
	def cc
		Gblock.new(self)
	end
	def cc1
		('a=gpop;'+self).cc
	end
	def cc2
		('b=gpop;a=gpop;'+self).cc
	end
	def cc3
		('c=gpop;b=gpop;a=gpop;'+self).cc
	end
	def order
		('b=gpop;a=gpop;a,b=b,a if a.class_id<b.class_id;'+self).cc
	end
end

var'[','$lb<<$stack.size'.cc
var']','gpush Garray.new($stack.slice!(($lb.pop||0)..-1))'.cc
var'~','gpush ~a'.cc1
var'`','gpush a.ginspect'.cc1
var';',''.cc1
var'.','$stack<<a<<a'.cc1
var'\\','$stack<<b<<a'.cc2
var'@','$stack<<b<<c<<a'.cc3
var'+','gpush a.addop(b)'.cc2
var'-','gpush a.subop(b)'.cc2
var'|','gpush a.uniop(b)'.cc2
var'&','gpush a.intop(b)'.cc2
var'^','gpush a.difop(b)'.cc2
var'*','gpush a*b'.order
var'/','gpush a/b'.order
var'%','gpush a%b'.order
var'=','gpush a.equalop(b)'.order
var'<','gpush a.ltop(b)'.order
var'>','gpush a.gtop(b)'.order
var'!','gpush a.notop'.cc1
var'?','gpush a.question(b)'.order
var'$','gpush (Numeric === a ? $stack[~a] : a.sort)'.cc1
var',','gpush case a
	when Numeric then Garray.new([*0...a])
	when Gblock then a.select(gpop)
	when Garray then (a.val.size)
	end'.cc1
var')','gpush a.rightparen'.cc1
var'(','gpush a.leftparen'.cc1

var'rand','gpush (rand([1,a].max))'.cc1
var'abs','gpush (a.abs)'.cc1
var'print','print a.to_gs'.cc1
var'if',"#{var'!'}.go;(gpop==0?a:b).go".cc2
var'do',"loop{a.go; #{var'!'}.go; break if gpop!=0}".cc1
var'while',"loop{a.go; #{var'!'}.go; break if gpop!=0; b.go}".cc2
var'until',"loop{a.go; #{var'!'}.go; break if gpop==0; b.go}".cc2
var'zip','gpush a.zip'.cc1
var'base','gpush b.base(a)'.cc2

'"\n":n;
{print n print}:puts;
{`puts}:p;
{1$if}:and;
{1$\if}:or;
{\!!{!}*}:xor;
'.compile.go
code.compile.go
gpush Garray.new($stack)
'puts'.compile.go
