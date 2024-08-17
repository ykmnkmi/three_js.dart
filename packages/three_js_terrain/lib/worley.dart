import 'dart:typed_data';

import 'package:three_js_math/three_js_math.dart';
import 'dart:math' as math;

import 'package:three_js_terrain/core.dart';  

///
/// A set of functions to calculate the 2D distance between two vectors.
///
/// The other alternatives are distanceTo (Euclidean) and distanceToSquared
/// (Euclidean squared).
///
extension TerrainVectort2 on Vector2{
  double distanceToManhattan(Vector2 b) {
    return (this.x - b.x).abs() + (this.y - b.y).abs();
  }
  double distanceToChebyshev(Vector2 b) {
    final c = (this.x - b.x).abs(),
        d = (this.y - b.y).abs();
    return c <= d ? d : c;
  }
  double distanceToQuadratic(Vector2 b) {
    final c = (this.x - b.x).abs(),
        d = (this.y - b.y).abs();
    return c*c + c*d + d*d;
  }
}

class Worley{
  ///
  /// Find the Voronoi centroid closest to the current terrain vertex.
  ///
  /// This approach is naive, but since the number of cells isn't typically
  /// very big, it's plenty fast enough.
  ///
  /// Alternatives approaches include using Fortune's algorithm or tracking
  /// cells based on a grid.
  ///
  int distanceToNearest(Vector2 coords, List<Vector2> points, DistanceToType distanceType) {
    int color = double.maxFinite.toInt();
    for (int k = 0; k < points.length; k++) {
      late final double d;
      if(distanceType == DistanceToType.manhattan){
        d = points[k].distanceToManhattan(coords);
      }
      else if(distanceType == DistanceToType.chebyshev){
        d = points[k].distanceToChebyshev(coords);
      }
      else if(distanceType == DistanceToType.quadratic){
        d = points[k].distanceToQuadratic(coords);
      }
      else{
        d = points[k].distanceToSquared(coords);
      }
      if (d < color) {
        color = d.toInt();
      }
    }
    return color;
  }

  ///
  /// Generate random terrain using Worley noise.
  /// 
  /// Worley noise is also known as Cell or Voronoi noise. It is generated by
  /// scattering a bunch of points in heightmap-space, then setting the height
  /// of every point in the heightmap based on how close it is to the closest
  /// scattered point (or the nth-closest point, but this results in
  /// heightmaps that don't look much like terrain).
  /// 
  /// [Float32List] g
  ///   The geometry's z-positions to modify with heightmap data.
  /// [TerrainOptions] options
  ///   A map of settings that control how the terrain is constructed and
  ///   displayed. Valid values are the same as those for the `options`
  ///   parameter of {@linkTerrain}(), plus three additional available
  ///   properties:
  ///   - `distanceType`: The name of a method to use to calculate the
  ///     distance between a point in the heightmap and a Voronoi centroid in
  ///     order to determine the height of that point. Available methods
  ///     include 'Manhattan', 'Chebyshev', 'Quadratic', 'Squared' (squared
  ///     Euclidean), and '' (the empty string, meaning Euclidean, the
  ///     default).
  ///   - `worleyDistanceTransformation`: A function that takes the distance
  ///     from a heightmap vertex to a Voronoi centroid and returns a relative
  ///     height for that vertex. Defaults to function(d) { return -d; }.
  ///     Interesting choices of algorithm include
  ///     `0.5 + 1.0 /// Math.cos((0.5*d-1) /// Math.PI) - d`, which produces
  ///     interesting stepped cones, and `-Math.sqrt(d)`, which produces sharp
  ///     peaks resembling stalagmites.
  ///   - `worleyDistribution`: A function to use to distribute Voronoi
  ///     centroids. Available methods include
  ///     `THREE.Terrain.Worley.randomPoints` (the default),
  ///     `THREE.Terrain.Worley.PoissonDisks`, and any function that returns
  ///     an array of `THREE.Vector2` instances. You can wrap the PoissonDisks
  ///     function to use custom parameters.
  ///   - `worleyPoints`: The number of Voronoi cells to use (must be at least
  ///     one). Calculated by default based on the size of the terrain.
  ///
  Worley(Float32List g, TerrainOptions options) {
    final points = (options.worleyDistribution ?? randomPoints)(options.xSegments, options.ySegments, options.worleyPoints);//
    final transform = options.worleyDistanceTransformation ?? (num d){return -d.toDouble();};
    final currentCoords = Vector2.zero();
    // The height of each heightmap vertex is the distance to the closest Voronoi centroid
    for (int i = 0, xl = options.xSegments + 1; i < xl; i++) {
      for (int j = 0; j < options.ySegments + 1; j++) {
        currentCoords.x = i*1.0;
        currentCoords.y = j*1.0;
        g[j*xl+i] = transform(distanceToNearest(currentCoords, points, options.distanceType));
      }
    }
    // We set the heights to distances so now we need to normalize
    Terrain.clamp(
      g, 
      TerrainOptions(
        maxHeight: options.maxHeight,
        minHeight: options.minHeight,
        stretch: true,
      )
    );
  }

  ///
  /// Randomly distribute points in space.
  ///
  List<Vector2> randomPoints(int width, int height, [int? numPoints]) {
    numPoints = numPoints ?? (math.sqrt(width * height * 0.025)).floor();
    numPoints = numPoints == 0?1:numPoints;
    final points = List.filled(numPoints, new Vector2());
    for (int i = 0; i < numPoints; i++) {
      points[i] = Vector2(
        math.Random().nextDouble() * width,
        math.Random().nextDouble() * height
      );
    }
    return points;
  }

  /// Utility functions for Poisson Disks.
  double removeAndReturnRandomElement(List<Vector2> arr) {
    return arr.removeAt((math.Random().nextDouble() * arr.length).floor())[0];
  }

  void putInGrid(grid, Vector2 point, cellSize) {
      final gx = (point.x / cellSize).floor(),
          gy = (point.y / cellSize).floor();
      if (!grid[gx]) grid[gx] = [];
      grid[gx][gy] = point;
  }

  bool inRectangle(Vector2 point, num width, num height) {
      return  point.x >= 0 && // jscs:ignore requireSpaceAfterKeywords
              point.y >= 0 &&
              point.x <= width+1 &&
              point.y <= height+1;
  }

  bool inNeighborhood(grid, Vector2 point, double minDist, double cellSize) {
      final gx = (point.x / cellSize).floor(),
          gy = (point.y / cellSize).floor();
      for (int x = gx - 1; x <= gx + 1; x++) {
          for (int y = gy - 1; y <= gy + 1; y++) {
              if (x != gx && y != gy) { //&& typeof grid[x] != 'undefined' && typeof grid[x][y] != 'undefined'
                  final cx = x * cellSize,
                      cy = y * cellSize;
                  if (math.sqrt((point.x - cx) * (point.x - cx) + (point.y - cy) * (point.y - cy)) < minDist) {
                      return true;
                  }
              }
          }
      }
      return false;
  }

  Vector2 generateRandomPointAround(point, minDist) {
      final radius = minDist * (math.Random().nextDouble() + 1),
          angle = 2 * math.pi * math.Random().nextDouble();
      return Vector2(
          point.x + radius * math.cos(angle),
          point.y + radius * math.sin(angle)
      );
  }

  ///
  /// Generate a set of points using Poisson disk sampling.
  ///
  /// Useful for clustering scattered meshes and Voronoi cells for Worley noise.
  ///
  /// Ported from pseudocode at http://devmag.org.za/2009/05/03/poisson-disk-sampling/
  ///
  /// [TerrainOptions] options
  ///   A map of settings that control how the resulting noise should be generated
  ///   (with the same parameters as the `options` parameter to the
  ///   `THREE.Terrain` function).
  ///
  /// return [List<Vector2>]
  ///   An array of points.
  ///
  List<Vector2> poissonDisks(width, height, numPoints, minDist) {
      numPoints = numPoints ?? (math.sqrt(width * height * 0.2)).floor() ?? 1;
      minDist = math.sqrt((width + height) * 2.5);
      if (minDist > numPoints * 0.67) minDist = numPoints * 0.67;
      double cellSize = minDist / math.sqrt(2);
      if (cellSize < 2) cellSize = 2;

      final grid = [];

      final List<Vector2> processList = [],
          samplePoints = [];

      final firstPoint = Vector2(
          math.Random().nextDouble() * width,
          math.Random().nextDouble() * height
      );
      processList.add(firstPoint);
      samplePoints.add(firstPoint);
      putInGrid(grid, firstPoint, cellSize);

      int count = 0;
      while (processList.isNotEmpty) {
          final point = removeAndReturnRandomElement(processList);
          for (int i = 0; i < numPoints; i++) {
              // optionally, minDist = perlin(point.x / width, point.y / height)
              final newPoint = generateRandomPointAround(point, minDist);
              if (inRectangle(newPoint, width, height) && !inNeighborhood(grid, newPoint, minDist, cellSize)) {
                  processList.add(newPoint);
                  samplePoints.add(newPoint);
                  putInGrid(grid, newPoint, cellSize);
                  if (samplePoints.length >= numPoints) break;
              }
          }
          if (samplePoints.length >= numPoints) break;
          // Sanity check
          if (++count > numPoints*numPoints) {
              break;
          }
      }
      return samplePoints;
  }
}