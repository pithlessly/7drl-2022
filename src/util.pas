{$mode objfpc}{$H+}
{$assertions+}
{$overflowchecks on}
{$rangechecks on}
{$scopedenums on}

unit Util;

interface

type Vec2 = record x: Int16; y: Int16; end;
function MkVec2(const x, y: Int16): Vec2;
operator= (const a, b: Vec2): Boolean;
operator+ (const a, b: Vec2): Vec2;
function Dist2(const a, b: Vec2): UInt32;

type Slope = record numer, denom: UInt16; end;
function MkSlope(const n, d: UInt16): Slope;
operator= (a, b: Slope): Boolean;
operator> (a, b: Slope): Boolean;
operator>= (a, b: Slope): Boolean;

implementation

function MkVec2(const x, y: Int16): Vec2;
begin
    result.x := x;
    result.y := y;
end;

operator= (const a, b: Vec2): Boolean;
begin
    result := (a.x = b.x) and (a.y = b.y);
end;

operator+ (const a, b: Vec2): Vec2;
begin
    result.x := a.x + b.x;
    result.y := a.y + b.y;
end;

function Dist2(const a, b: Vec2): UInt32;
var dx, dy: Int32;
begin
    dx := Int32(a.x) - Int32(b.x);
    dy := Int32(a.y) - Int32(b.y);
    result := UInt32(dx * dx) + UInt32(dy * dy);
end;

function MkSlope(const n, d: UInt16): Slope;
    function Gcd(n, d: UInt16): UInt16;
    var tmp: UInt16;
    begin
        while d <> 0 do
        begin
            tmp := n mod d;
            n := d;
            d := tmp;
        end;
        result := n;
    end;
var
    gcd_: UInt16;
begin
    Assert(d > 0);
    gcd_ := Gcd(n, d);
    result.numer := n div gcd_;
    result.denom := d div gcd_;
end;

operator= (a, b: Slope): Boolean;
begin
    result := (UInt32(a.numer) * UInt32(b.denom))
            = (UInt32(a.denom) * UInt32(b.numer));
end;

operator> (a, b: Slope): Boolean;
begin
    result := (UInt32(a.numer) * UInt32(b.denom))
            > (UInt32(a.denom) * UInt32(b.numer));
end;

operator>= (a, b: Slope): Boolean;
begin
    result := (UInt32(a.numer) * UInt32(b.denom))
           >= (UInt32(a.denom) * UInt32(b.numer));
end;

end.
