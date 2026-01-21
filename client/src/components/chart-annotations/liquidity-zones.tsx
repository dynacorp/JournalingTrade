import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface LiquidityZonesProps {
  equalHighs: number[];
  equalLows: number[];
  sweepDetected: boolean;
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
}

export function LiquidityZones({
  equalHighs,
  equalLows,
  sweepDetected,
  priceRange,
  imageWidth,
  imageHeight,
}: LiquidityZonesProps) {
  const triangleSize = Math.max(8, imageHeight * 0.015);
  const fontSize = Math.max(11, imageHeight * 0.018);

  return (
    <g className="liquidity-zones">
      {/* Equal Highs - Orange with upward triangles */}
      {equalHighs.map((level, i) => {
        const y = priceToY(level, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;
        return (
          <g key={`eq-high-${i}`}>
            {/* Dotted line */}
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke="#f97316"
              strokeWidth="1.5"
              strokeDasharray="4 4"
              strokeOpacity="0.7"
            />
            {/* Triangle markers pointing up (liquidity above) */}
            <polygon
              points={`${imageWidth * 0.1},${y} ${imageWidth * 0.1 - triangleSize},${y + triangleSize * 1.5} ${imageWidth * 0.1 + triangleSize},${y + triangleSize * 1.5}`}
              fill="#f97316"
              fillOpacity="0.8"
            />
            <polygon
              points={`${imageWidth * 0.5},${y} ${imageWidth * 0.5 - triangleSize},${y + triangleSize * 1.5} ${imageWidth * 0.5 + triangleSize},${y + triangleSize * 1.5}`}
              fill="#f97316"
              fillOpacity="0.8"
            />
            <polygon
              points={`${imageWidth * 0.9},${y} ${imageWidth * 0.9 - triangleSize},${y + triangleSize * 1.5} ${imageWidth * 0.9 + triangleSize},${y + triangleSize * 1.5}`}
              fill="#f97316"
              fillOpacity="0.8"
            />
            {/* Label */}
            <rect
              x={5}
              y={y - fontSize / 2 - 2}
              width={65}
              height={fontSize + 4}
              fill="#f97316"
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={10}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="600"
              dominantBaseline="middle"
              fontFamily="monospace"
            >
              EQH
            </text>
          </g>
        );
      })}

      {/* Equal Lows - Cyan with downward triangles */}
      {equalLows.map((level, i) => {
        const y = priceToY(level, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;
        return (
          <g key={`eq-low-${i}`}>
            {/* Dotted line */}
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke="#06b6d4"
              strokeWidth="1.5"
              strokeDasharray="4 4"
              strokeOpacity="0.7"
            />
            {/* Triangle markers pointing down (liquidity below) */}
            <polygon
              points={`${imageWidth * 0.1},${y} ${imageWidth * 0.1 - triangleSize},${y - triangleSize * 1.5} ${imageWidth * 0.1 + triangleSize},${y - triangleSize * 1.5}`}
              fill="#06b6d4"
              fillOpacity="0.8"
            />
            <polygon
              points={`${imageWidth * 0.5},${y} ${imageWidth * 0.5 - triangleSize},${y - triangleSize * 1.5} ${imageWidth * 0.5 + triangleSize},${y - triangleSize * 1.5}`}
              fill="#06b6d4"
              fillOpacity="0.8"
            />
            <polygon
              points={`${imageWidth * 0.9},${y} ${imageWidth * 0.9 - triangleSize},${y - triangleSize * 1.5} ${imageWidth * 0.9 + triangleSize},${y - triangleSize * 1.5}`}
              fill="#06b6d4"
              fillOpacity="0.8"
            />
            {/* Label */}
            <rect
              x={5}
              y={y - fontSize / 2 - 2}
              width={65}
              height={fontSize + 4}
              fill="#06b6d4"
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={10}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="600"
              dominantBaseline="middle"
              fontFamily="monospace"
            >
              EQL
            </text>
          </g>
        );
      })}

      {/* Sweep indicator if detected */}
      {sweepDetected && (
        <g className="sweep-indicator">
          <rect
            x={imageWidth / 2 - 45}
            y={10}
            width={90}
            height={24}
            fill="#dc2626"
            fillOpacity="0.9"
            rx="4"
          />
          <text
            x={imageWidth / 2}
            y={22}
            fill="white"
            fontSize={12}
            fontWeight="700"
            textAnchor="middle"
            dominantBaseline="middle"
          >
            SWEEP
          </text>
        </g>
      )}
    </g>
  );
}
