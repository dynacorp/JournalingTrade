import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface LevelLinesProps {
  supportLevels: number[];
  resistanceLevels: number[];
  srFlips: number[];
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
}

export function LevelLines({
  supportLevels,
  resistanceLevels,
  srFlips,
  priceRange,
  imageWidth,
  imageHeight,
}: LevelLinesProps) {
  const labelOffset = 10;
  const fontSize = Math.max(12, imageHeight * 0.02);

  return (
    <g className="level-lines">
      {/* Resistance levels - Red */}
      {resistanceLevels.map((level, i) => {
        const y = priceToY(level, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;
        return (
          <g key={`resistance-${i}`}>
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke="#ef4444"
              strokeWidth="2"
              strokeOpacity="0.8"
            />
            <rect
              x={imageWidth - 80}
              y={y - fontSize / 2 - 2}
              width={75}
              height={fontSize + 4}
              fill="#ef4444"
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={imageWidth - labelOffset}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="600"
              textAnchor="end"
              dominantBaseline="middle"
              fontFamily="monospace"
            >
              R: {level.toFixed(level >= 100 ? 2 : 5)}
            </text>
          </g>
        );
      })}

      {/* Support levels - Green */}
      {supportLevels.map((level, i) => {
        const y = priceToY(level, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;
        return (
          <g key={`support-${i}`}>
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke="#22c55e"
              strokeWidth="2"
              strokeOpacity="0.8"
            />
            <rect
              x={imageWidth - 80}
              y={y - fontSize / 2 - 2}
              width={75}
              height={fontSize + 4}
              fill="#22c55e"
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={imageWidth - labelOffset}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="600"
              textAnchor="end"
              dominantBaseline="middle"
              fontFamily="monospace"
            >
              S: {level.toFixed(level >= 100 ? 2 : 5)}
            </text>
          </g>
        );
      })}

      {/* S/R Flip levels - Purple/Magenta */}
      {srFlips.map((level, i) => {
        const y = priceToY(level, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;
        return (
          <g key={`srflip-${i}`}>
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke="#a855f7"
              strokeWidth="2"
              strokeDasharray="8 4"
              strokeOpacity="0.8"
            />
            <rect
              x={imageWidth - 90}
              y={y - fontSize / 2 - 2}
              width={85}
              height={fontSize + 4}
              fill="#a855f7"
              fillOpacity="0.9"
              rx="2"
            />
            <text
              x={imageWidth - labelOffset}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="600"
              textAnchor="end"
              dominantBaseline="middle"
              fontFamily="monospace"
            >
              FLIP: {level.toFixed(level >= 100 ? 2 : 5)}
            </text>
          </g>
        );
      })}
    </g>
  );
}
