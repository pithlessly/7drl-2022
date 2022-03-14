{$mode objfpc}{$H+}
{$assertions+}
{$overflowchecks on}
{$rangechecks on}
{$scopedenums on}

unit World;

interface

uses Util, Vision;

type
    Player = record loc: Vec2; end;

    TileKind = (empty, solid);
    Tile = record
        kind: TileKind;
        is_visible: Boolean;
    end;
    TilePtr = ^Tile;

    Map = object
    private
        width, height: UInt16;
        tiles: array of Tile;
        procedure ResetVisibility;
    public
        constructor Init(const width_, height_: UInt16);
        function TryGetTile(const at: Vec2; var t: TilePtr): Boolean;
        function GetTile(const at: Vec2): TilePtr;
        procedure RecomputeVisibility(const origin: Vec2);
    end;

implementation

constructor Map.Init(const width_, height_: UInt16);
var i: NativeUInt;
begin
    width := width_;
    height := height_;
    SetLength(tiles, width * height);
    for i := Low(tiles) to High(tiles) do
        if (Random(5) = 0) then
            tiles[i].kind := TileKind.solid
        else
            tiles[i].kind := TileKind.empty;
    ResetVisibility;
end;

procedure Map.ResetVisibility;
var i: NativeUInt;
begin
    for i := Low(tiles) to high(tiles) do
        tiles[i].is_visible := false;
end;

function Map.TryGetTile(const at: Vec2; var t: TilePtr): Boolean;
var idx: NativeUInt;
begin
    result := (at.x in [0..width - 1]) and (at.y in [0..height - 1]);
    if not result then
        exit;
    idx := NativeUInt(at.y) * NativeUInt(width) + NativeUInt(at.x);
    t := @tiles[idx];
end;

function Map.GetTile(const at: Vec2): TilePtr;
begin
    Assert(Map.TryGetTile(at, result), 'out of bounds');
end;

type
    MapPtr = ^Map;
    VisibilityAdapter = object
    private
        inner: MapPtr;
    public
        constructor Init(const inner_: MapPtr);
        function IsOpaque(const at: Vec2): Boolean;
        function VisibilityDistance(const at: Vec2): UInt32;
        procedure MarkVisible(const at: Vec2);
    end;

constructor VisibilityAdapter.Init(const inner_: MapPtr);
begin
    inner := inner_;
end;

function VisibilityAdapter.IsOpaque(const at: Vec2): Boolean;
var t: ^Tile;
begin
    result := inner^.TryGetTile(at, t) and (t^.kind = TileKind.solid);
end;

function VisibilityAdapter.VisibilityDistance(const at: Vec2): UInt32;
begin
    result := Dist2(at, MkVec2(0, 0));
end;

procedure VisibilityAdapter.MarkVisible(const at: Vec2);
var t: TilePtr;
begin
    t := nil;
    if inner^.TryGetTile(at, t) then
        t^.is_visible := true;
end;

procedure Map.RecomputeVisibility(const origin: Vec2);
const
    MAX_DISTANCE = 50;
var
    adapter: VisibilityAdapter;
    vc: specialize VisionComputation<VisibilityAdapter>;
begin
    ResetVisibility;
    adapter.Init(@self);
    vc.Init(adapter, origin, MAX_DISTANCE);
    vc.Compute;
end;

end.
