/*
	TopZIndex 1.2 (October 21, 2010) plugin for jQuery
	http://topzindex.googlecode.com/
	Copyright (c) 2009-2011 Todd Northrop
	http://www.speednet.biz/
	Licensed under GPL 3, see  <http://www.gnu.org/licenses/>
*/
(function(a){a.topZIndex=function(b){return Math.max(0,Math.max.apply(null,a.map((b||"*")==="*"?a.makeArray(document.getElementsByTagName("*")):a(b),function(b){return parseFloat(a(b).css("z-index"))||null})))};a.fn.topZIndex=function(b){if(this.length===0)return this;b=a.extend({increment:1},b);var c=a.topZIndex(b.selector),d=b.increment;return this.each(function(){this.style.zIndex=c+=d})}})(jQuery);