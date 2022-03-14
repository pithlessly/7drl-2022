{$mode objfpc}{$H+}
{$assertions+}
{$overflowchecks on}
{$rangechecks on}
{$scopedenums on}

{ An implementation of Adam Milazzo's algorithm for tile visibility, which can be found at
  <http://www.adammil.net/blog/v125_Roguelike_Vision_Algorithms.html>.
}

unit Vision;

interface

uses Util;

type
    { Wld should provide the following API:
        function Wld.IsOpaque(Vec2): Boolean;          // whether a given point is solid
        function Wld.VisibilityDistance(Vec2): UInt32; // distance to origin
        procedure Wld.MarkVisible(Vec2);               // mark a given point as visible
    }
    generic VisionComputation<Wld> = object
    private
        type Octant = UInt8;
    private
        world: Wld;
        origin: Vec2;
        max_distance: UInt32;
        cur_octant: Octant;

        function Clamp(const a: UInt32): Int16; static;

        function AdjustForOctant(const p: Vec2): Vec2;
        function IsOpaque(const p: Vec2): Boolean;
        procedure MarkVisible(const p: Vec2);

        function SectorColumnTop   (const top:    Slope; const x: Int16): Int16;
        function SectorColumnBottom(const bottom: Slope; const x: Int16): Int16;
        procedure ScanColumn(
            var top, bottom: Slope;
            const x, max_y, min_y: Int16;
            var halt_now: Boolean
        );
        procedure ComputeSector(top, bottom: Slope; const min_x: Int16);
    public
        constructor Init(const world_: Wld; const origin_: Vec2; const max_distance_: UInt32);
        procedure Compute;
    end;

implementation

constructor VisionComputation.Init(const world_: Wld; const origin_: Vec2; const max_distance_: UInt32);
begin
    world := world_;
    origin := origin_;
    max_distance := max_distance_;
end;

{ The algorithm works by dividing up the world around the origin into eight triangular regions.
  Each region is bounded by one orthogonal line and one diagonal line, and coordinates are
  transformed such that vision computation in each octave can treat the orthogonal bounding line
  as 'y = 0' and and the diagonal bounding line is 'y = x'. }
function VisionComputation.AdjustForOctant(const p: Vec2): Vec2;
var x, y: Int16;
begin
    case cur_octant of
        0: begin x :=  p.x; y := -p.y; end;
        1: begin x :=  p.y; y := -p.x; end;
        2: begin x := -p.y; y := -p.x; end;
        3: begin x := -p.x; y := -p.y; end;
        4: begin x := -p.x; y :=  p.y; end;
        5: begin x := -p.y; y :=  p.x; end;
        6: begin x :=  p.y; y :=  p.x; end;
        7: begin x :=  p.x; y :=  p.y; end;
    else
        Assert(false, 'invalid octant');
    end;
    result.x := origin.x + x;
    result.y := origin.y + y;
end;

function VisionComputation.IsOpaque(const p: Vec2): Boolean;
begin
    result := world.IsOpaque(AdjustForOctant(p));
end;

procedure VisionComputation.MarkVisible(const p: Vec2);
begin
    world.MarkVisible(AdjustForOctant(p));
end;

function VisionComputation.Clamp(const a: UInt32): Int16;
const MAX_I16 = 32767;
begin
    if a > MAX_I16 then
        result := MAX_I16
    else
        result := Int16(a);
end;

function VisionComputation.SectorColumnTop(const top: Slope; const x: Int16): Int16;
var
    n, d: UInt16;
    ax: Int16;
begin
    n := top.numer; d := top.denom;
    if n = d then { slope = 1 }
    begin
        result := x;
        exit;
    end;

    result := ((2*x - 1) * n + d) div (2*d);

    if IsOpaque(MkVec2(x, result)) then
    begin
        if (top >= MkSlope(2*result + 1, 2*x))
           and not IsOpaque(MkVec2(x, result + 1))
        then
            Inc(result);
        exit;
    end;

    ax := 2*x;
    if IsOpaque(MkVec2(x + 1, result + 1)) then
        Inc(ax);
    if top > MkSlope(2*result + 1, ax) then
        Inc(result);
end;

function VisionComputation.SectorColumnBottom(const bottom: Slope; const x: Int16): Int16;
var
    n, d: UInt16;
begin
    n := bottom.numer; d := bottom.denom;
    if n = 0 then { slope = 0 }
    begin
        result := 0;
        exit;
    end;

    result := ((2*x - 1) * n + d) div (2*d);
    if (bottom >= MkSlope(2*result + 1, 2*x))
        and     IsOpaque(MkVec2(x, result))
        and not IsOpaque(MkVec2(x, result + 1))
    then
        Inc(result);
end;

procedure VisionComputation.ScanColumn(
    var top, bottom: Slope;
    const x, max_y, min_y: Int16;
    var halt_now: Boolean
);
var
    y: Int16;
    cell_loc: Vec2;
    cell_slope: Slope;
    is_top_cell, cell_is_opaque, last_cell_was_opaque: Boolean;
    tmp_slope: Slope;
begin
    Assert(not halt_now);
    is_top_cell := true;
    last_cell_was_opaque := true; // dummy value, never accessed in loop
                                  // when `is_top_cell` is set
    for y := max_y downto min_y do
    begin
        cell_loc := MkVec2(x, y);
        cell_slope := MkSlope(y, x);
        if (world.VisibilityDistance(cell_loc) > max_distance) then
            continue;
        // check if this cell should be visible
        if ((y <> max_y) or (top >= cell_slope)) and
           ((y <> min_y) or (cell_slope >= bottom))
        then
            MarkVisible(cell_loc);
        // no need to compute opacity on the last iteration
        if x = max_distance then
            continue;
        cell_is_opaque := IsOpaque(cell_loc);
        if (not is_top_cell) and (last_cell_was_opaque <> cell_is_opaque) then
        begin
            tmp_slope := MkSlope(2*y + 1, 2*x);
            if cell_is_opaque then
                if top > tmp_slope then
                    if y = min_y then
                    begin
                        bottom := tmp_slope;
                        break;
                    end
                    else
                        ComputeSector(top, tmp_slope, x + 1)
                else
                    if y = min_y then
                    begin
                        halt_now := true;
                        exit;
                    end
                    else
                    begin end
            else
                if bottom >= tmp_slope then
                begin
                    halt_now := true;
                    exit;
                end
                else
                    top := tmp_slope;
        end;
        is_top_cell := false;
        last_cell_was_opaque := cell_is_opaque;
    end;

    { this is true if `is_top_cell`, or if set normally }
    halt_now := last_cell_was_opaque;
end;

procedure VisionComputation.ComputeSector(top, bottom: Slope; const min_x: Int16);
var
    x: Int16;
    halt_now: Boolean;
begin
    halt_now := false;
    for x := min_x to Clamp(max_distance - 1) do
    begin
        ScanColumn(
            top, bottom,
            x,
            SectorColumnTop(top, x),
            SectorColumnBottom(bottom, x),
            halt_now
        );
        if halt_now then
            break;
    end;
end;

procedure VisionComputation.Compute;
var oct: Octant;
begin
    world.MarkVisible(origin);
    for oct := 0 to 7 do
    begin
        cur_octant := oct;
        ComputeSector(MkSlope(1, 1), MkSlope(0, 1), 1);
    end;
end;

end.
