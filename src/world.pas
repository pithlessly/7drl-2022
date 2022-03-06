{$mode objfpc}{$H+}
{$assertions+}
{$overflowchecks on}
{$rangechecks on}
{$scopedenums on}

unit World;

interface

type Vec2 = record x: Int16; y: Int16; end;
function MkVec2(const x, y: Int16): Vec2;
operator= (const a, b: Vec2): Boolean;
function Dist2(const a, b: Vec2): Int32;

type
    Player = record loc: Vec2; end;

    TileClass = (empty, solid);
    Map = object
    private
        width, height: UInt16;
        tiles: array of TileClass;
    public
        constructor Init(const width_, height_: UInt16);
        function GetTile(const at: Vec2): TileClass;
    end;

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

function Dist2(const a, b: Vec2): Int32;
var dx, dy: Int32;
begin
    dx := Int32(a.x) - Int32(b.x);
    dy := Int32(a.y) - Int32(b.y);
    result := dx * dx + dy * dy;
end;

constructor Map.Init(const width_, height_: UInt16);
var i: NativeUInt;
begin
    width := width_;
    height := height_;
    SetLength(tiles, width * height);
    for i := Low(tiles) to High(tiles) do
        if (Random(5) = 0) then
            tiles[i] := TileClass.solid
        else
            tiles[i] := TileClass.empty;
end;

function Map.GetTile(const at: Vec2): TileClass;
var idx: NativeUInt;
begin
    assert((0 <= at.x) and (at.x < width), 'x out of bounds');
    assert((0 <= at.y) and (at.y < height), 'y out of bounds');
    idx := NativeUInt(at.y) * NativeUInt(width) + NativeUInt(at.x);
    result := tiles[idx];
end;

end.
