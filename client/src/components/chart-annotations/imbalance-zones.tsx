import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface FvgZone {
  start: number;
  end: number;
  filled: boolean;
}

interface ImbalanceZonesProps {
  zones: FvgZone[];
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
}

export function ImbalanceZones({
  zones,
  priceRange,
  imageWidth,
  imageHeight,
}: ImbalanceZonesProps) {
  const fontSize = Math.max(10, imageHeight * 0.016);

  return (
    <g className="imbalance-zones">
      {zones.map((zone, i) => {
        const y1 = priceToY(zone.start, priceRange, imageHeight);
        const y2 = priceToY(zone.end, priceRange, imageHeight);
        const top = Math.min(y1, y2);
        const height = Math.abs(y2 - y1);

        // Skip if zone is outside visible area
        if (top > imageHeight || top + height < 0) return null;

        const fillColor = zone.filled ? "#6b7280" : "#eab308"; // Gray if filled, yellow if unfilled
        const labelText = zone.filled ? "FVG (FILLED)" : "FVG";

        return (
          <g key={`fvg-${i}`}>
            {/* Diagonal stripe pattern fill */}
            <rect
              x={imageWidth * 0.1}
              y={top}
              width={imageWidth * 0.8}
              height={Math.max(height, 4)}
              fill={zone.filled ? "rgba(107, 114, 128, 0.2)" : "url(#fvg-pattern)"}
              stroke={fillColor}
              strokeWidth="1"
              strokeOpacity="0.5"
            />
            {/* Top border */}
            <line
              x1={imageWidth * 0.1}
              y1={top}
              x2={imageWidth * 0.9}
              y2={top}
              stroke={fillColor}
              strokeWidth="1.5"
              strokeDasharray={zone.filled ? "4 2" : "none"}
              strokeOpacity="0.8"
            />
            {/* Bottom border */}
            <line
              x1={imageWidth * 0.1}
              y1={top + height}
              x2={imageWidth * 0.9}
              y2={top + height}
              stroke={fillColor}
              strokeWidth="1.5"
              strokeDasharray={zone.filled ? "4 2" : "none"}
              strokeOpacity="0.8"
            />
            {/* Label */}
            <rect
              x={imageWidth * 0.5 - 35}
              y={top + height / 2 - (fontSize + 4) / 2}
              width={zone.filled ? 80 : 40}
              height={fontSize + 4}
              fill={fillColor}
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={imageWidth * 0.5}
              y={top + height / 2}
              fill={zone.filled ? "#fff" : "#000"}
              fontSize={fontSize}
              fontWeight="700"
              textAnchor="middle"
              dominantBaseline="middle"
            >
              {labelText}
            </text>
          </g>
        );
      })}
    </g>
  );
}
