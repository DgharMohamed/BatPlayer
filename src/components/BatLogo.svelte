<script lang="ts">
  let { size = 64 }: { size?: number } = $props();
</script>

<!-- Minimal bat-wing mark: two scalloped wings around a small eared head. -->
<svg
  width={size}
  height={(size * 44) / 64}
  viewBox="0 0 64 44"
  fill="none"
  xmlns="http://www.w3.org/2000/svg"
  aria-hidden="true"
>
  <g fill="var(--accent)">
    <path
      d="M31 9 C27.5 3.5 17 1.5 4 5.5 C9.5 8 12.5 12.5 13 18.5
         C17 15.5 21 16.5 23 20.5 C26 18 29 19 30.5 23
         C31.2 18.5 31.3 13.5 31 9 Z"
    />
    <path
      d="M33 9 C36.5 3.5 47 1.5 60 5.5 C54.5 8 51.5 12.5 51 18.5
         C47 15.5 43 16.5 41 20.5 C38 18 35 19 33.5 23
         C32.8 18.5 32.7 13.5 33 9 Z"
    />
    <path
      d="M28.7 7.2 C29.5 5.4 30.3 4 31 3.1 L31.9 5.3 L32 5.2 L32.1 5.3
         L33 3.1 C33.7 4 34.5 5.4 35.3 7.2 C34.2 8.3 33.1 8.8 32 8.9
         C30.9 8.8 29.8 8.3 28.7 7.2 Z"
    />
  </g>
</svg>
